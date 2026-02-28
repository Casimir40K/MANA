classdef LineSearch
    %LINESEARCH  Static helpers for line search and LM linear solve.

    methods (Static)

        function [accepted, x_new, r_new, alpha, bt, stagnationReject] = ...
                backtrackingLineSearch(tryResidualsFcn, x, dx, rnU, rnW, w, damping, maxIncreaseRatio)
            %BACKTRACKINGLINESEARCH  Backtracking with weighted/unweighted criteria.
            if nargin < 8, maxIncreaseRatio = 0.02; end
            alpha = damping;
            bt = 0;
            accepted = false;
            stagnationReject = false;
            x_new = x;
            r_new = nan(size(dx));

            decreaseTol = 1e-8;
            noiseTol = 1e-14;
            strictTargetW = rnW * (1 - decreaseTol);
            maxTargetU = rnU * (1 + max(0, maxIncreaseRatio));
            flatSeen = false;

            while bt < 30
                xCand = x + alpha*dx;
                [rCand, okCand] = tryResidualsFcn(xCand);
                if okCand
                    rnUCand = norm(rCand);
                    rnWCand = norm(w .* rCand);
                    if rnWCand <= strictTargetW && rnUCand <= maxTargetU
                        accepted = true;
                        x_new = xCand;
                        r_new = rCand;
                        return
                    end
                    if rnWCand <= rnW * (1 + noiseTol) || rnUCand <= rnU * (1 + noiseTol)
                        flatSeen = true;
                    end
                end
                alpha = alpha * 0.5;
                bt = bt + 1;
                if alpha < 1e-10
                    break;
                end
            end

            stagnationReject = flatSeen;
        end

        function dx = solveLinearLM(J, b, w)
            %SOLVELINEARLM  Levenberg-Marquardt damped linear solve.
            Jw = J .* w;
            bw = b .* w;
            n = size(J,2);
            JTJ = Jw.' * Jw;  JTb = Jw.' * bw;
            lambda = 1e-6 * max(1, trace(JTJ)/max(1,n));
            I = eye(n);
            for it = 1:12
                dx = (JTJ + lambda*I) \ JTb;
                if all(isfinite(dx)), return; end
                lambda = lambda * 10;
            end
            dx = zeros(n,1);
        end
    end
end
