classdef JacobianEngine
    %JACOBIANENGINE  Static helpers for finite-difference Jacobian computation.
    %
    %   All methods are static. ProcessSolver delegates to these, passing
    %   a context struct with the state they need.

    methods (Static)

        function [J, sparsityPattern, columnColors, nColors] = fdJacobianSafe(x, r0, ctx)
            %FDJACOBIANSAFE  Dispatcher: compressed or column-wise FD Jacobian.
            %   ctx fields: tryResidualsFcn, fdEps, map, fdScheme, fdCentralColumns,
            %               sparsityPattern, columnColors, nColors
            n = numel(x);

            sparsityPattern = ctx.sparsityPattern;
            columnColors = ctx.columnColors;
            nColors = ctx.nColors;

            % Detect sparsity pattern on first call
            if isempty(sparsityPattern)
                [sparsityPattern, columnColors, nColors] = ...
                    proc.solver.JacobianEngine.detectSparsityPattern(x, r0, ctx);
            end

            % Use graph-coloring compressed FD if coloring is available
            if nColors > 0 && nColors < n
                J = proc.solver.JacobianEngine.fdJacobianCompressed( ...
                    x, r0, ctx, sparsityPattern, columnColors, nColors);
                return
            end

            % Fallback: standard column-by-column FD
            J = proc.solver.JacobianEngine.fdJacobianColumnwise(x, r0, ctx);
        end

        function J = fdJacobianColumnwise(x, r0, ctx)
            n = numel(x); m = numel(r0);
            J = zeros(m,n);
            tryRes = ctx.tryResidualsFcn;

            steps = zeros(n, 1);
            isCentral = false(n, 1);
            for k = 1:n
                steps(k) = proc.solver.JacobianEngine.fdStepForColumn(k, x(k), ctx);
                isCentral(k) = proc.solver.JacobianEngine.useCentralDifferenceForColumn(k, ctx);
            end

            for k = 1:n
                step = steps(k);
                if isCentral(k)
                    xPlus = x; xMinus = x;
                    xPlus(k) = xPlus(k) + step;
                    xMinus(k) = xMinus(k) - step;
                    [rPlus, okPlus] = tryRes(xPlus);
                    [rMinus, okMinus] = tryRes(xMinus);
                    if okPlus && okMinus
                        J(:,k) = (rPlus - rMinus) / (2 * step);
                    elseif okPlus
                        J(:,k) = (rPlus - r0) / step;
                    elseif okMinus
                        J(:,k) = (r0 - rMinus) / step;
                    else
                        J(:,k) = 0;
                    end
                else
                    x2 = x; x2(k) = x2(k) + step;
                    [r2, ok] = tryRes(x2);
                    if ~ok
                        J(:,k) = 0;
                    else
                        J(:,k) = (r2 - r0) / step;
                    end
                end
            end
        end

        function J = fdJacobianCompressed(x, r0, ctx, sparsityPattern, columnColors, nColors)
            n = numel(x); m = numel(r0);
            J = zeros(m, n);
            tryRes = ctx.tryResidualsFcn;

            for c = 1:nColors
                cols = find(columnColors == c);
                if isempty(cols), continue; end

                steps = zeros(numel(cols), 1);
                for j = 1:numel(cols)
                    steps(j) = proc.solver.JacobianEngine.fdStepForColumn(cols(j), x(cols(j)), ctx);
                end

                xPert = x;
                for j = 1:numel(cols)
                    xPert(cols(j)) = xPert(cols(j)) + steps(j);
                end

                [rPert, okPert] = tryRes(xPert);
                if ~okPert
                    for j = 1:numel(cols)
                        k = cols(j);
                        x2 = x; x2(k) = x2(k) + steps(j);
                        [r2, ok] = tryRes(x2);
                        if ok
                            rows = sparsityPattern(:, k);
                            J(rows, k) = (r2(rows) - r0(rows)) / steps(j);
                        end
                    end
                    continue
                end

                for j = 1:numel(cols)
                    k = cols(j);
                    rows = sparsityPattern(:, k);
                    J(rows, k) = (rPert(rows) - r0(rows)) / steps(j);
                end
            end
        end

        function step = fdStepForColumn(colIdx, xVal, ctx)
            if colIdx <= numel(ctx.map)
                varType = ctx.map(colIdx).var;
            else
                varType = '?';
            end
            switch varType
                case 'a'
                    step = 1e-6 * max(1, abs(xVal));
                otherwise
                    step = ctx.fdEps * max(1, abs(xVal));
            end
        end

        function [sp, colors, nColors] = detectSparsityPattern(x, r0, ctx)
            n = numel(x); m = numel(r0);
            sp = false(m, n);
            dropTol = 1e-14;
            tryRes = ctx.tryResidualsFcn;

            for k = 1:n
                step = proc.solver.JacobianEngine.fdStepForColumn(k, x(k), ctx);
                x2 = x; x2(k) = x2(k) + step;
                [r2, ok] = tryRes(x2);
                if ok
                    sp(:, k) = abs(r2 - r0) > dropTol * max(1, abs(r0));
                else
                    sp(:, k) = true;
                end
            end

            colors = proc.solver.JacobianEngine.greedyColumnColoring(sp);
            nColors = max(colors);
        end

        function colors = greedyColumnColoring(sp)
            n = size(sp, 2);
            colors = zeros(n, 1);
            for k = 1:n
                rowsK = sp(:, k);
                conflictColors = zeros(0, 1);
                for j = 1:k-1
                    if colors(j) > 0 && any(rowsK & sp(:, j))
                        conflictColors(end+1) = colors(j); %#ok<AGROW>
                    end
                end
                c = 1;
                usedColors = unique(conflictColors);
                while any(c == usedColors)
                    c = c + 1;
                end
                colors(k) = c;
            end
        end

        function tf = useCentralDifferenceForColumn(idx, ctx)
            scheme = lower(strtrim(char(ctx.fdScheme)));
            switch scheme
                case 'central'
                    tf = true;
                case 'mixed'
                    tf = any(idx == ctx.fdCentralColumns);
                otherwise
                    tf = false;
            end
        end

        function [J, accepted] = tryBroydenUpdate(J, s, y, minStepNorm2, minRcond)
            accepted = false;
            if isempty(J) || norm(s)^2 < minStepNorm2
                return
            end
            Jnew = J + ((y - J*s) * s.') / (s.' * s);
            if any(~isfinite(Jnew(:)))
                return
            end
            if rcond(Jnew) < minRcond
                return
            end
            J = Jnew;
            accepted = true;
        end
    end
end
