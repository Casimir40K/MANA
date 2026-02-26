classdef SensitivityTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = SensitivityTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function onRunSensitivity(obj)
            obj.Services.syncStreamsFromTable();
            if isempty(obj.State.streams) || isempty(obj.State.units)
                obj.Services.alertError('Add streams and units first.');
                return;
            end

            paramChoice = obj.Services.getSensParamChoice();
            vMin = obj.Services.getSensMin();
            vMax = obj.Services.getSensMax();
            nPts = round(obj.Services.getSensNpts());
            outStreamName = obj.Services.getSensOutputStream();
            outFieldStr = obj.Services.getSensOutputField();
            sensMaxIt = obj.Services.getSensMaxIter();
            sensTol = obj.Services.getSensTol();

            vals = linspace(vMin, vMax, nPts);
            results = nan(1, nPts);

            origVal = obj.getSensParamValue(paramChoice);

            obj.Services.clearSensitivityAxes();
            obj.Services.setStatus('Running sensitivity...');
            obj.Services.setSensitivityStatus(sprintf('Running 0/%d ...', nPts));
            obj.Services.setSensitivityRunEnabled(false);
            drawnow;

            for p = 1:nPts
                try
                    obj.applySensParam(paramChoice, vals(p));
                    fs = obj.Services.buildFlowsheet();
                    fs.solve('maxIter',sensMaxIt,'tolAbs',sensTol,'autoScale',true,'printToConsole',false);
                    results(p) = obj.extractOutput(outStreamName, outFieldStr);
                catch
                    results(p) = NaN;
                end
                obj.Services.setSensitivityStatus(sprintf('Running %d/%d ...', p, nPts));
                drawnow limitrate;
            end

            if ~isnan(origVal)
                obj.applySensParam(paramChoice, origVal);
            end

            obj.Services.setSensitivityRunEnabled(true);

            paramLabel = strrep(paramChoice, '_', '\_');
            obj.Services.plotSensitivity(vals, results, paramLabel, outStreamName, outFieldStr);
            nConv = sum(~isnan(results));
            statusMsg = sprintf('Sensitivity: %d/%d converged (maxIter=%d, tol=%.1e).', ...
                nConv, nPts, sensMaxIt, sensTol);
            obj.Services.setSensitivityStatus(statusMsg);
            obj.Services.setStatus(statusMsg);
        end

        function applySensParam(obj, paramChoice, val)
            [unitIdx, fieldName, vecIdx, streamName] = obj.parseSensParam(paramChoice);
            if ~isempty(unitIdx) && unitIdx <= numel(obj.State.units) && ~isempty(fieldName)
                u = obj.State.units{unitIdx};
                if ~isempty(vecIdx) && isprop(u, fieldName)
                    v = u.(fieldName);
                    v(vecIdx) = val;
                    u.(fieldName) = v;
                elseif isprop(u, fieldName)
                    u.(fieldName) = val;
                end
            elseif ~isempty(streamName) && ~isempty(fieldName)
                s = obj.Services.findStream(streamName);
                if ~isempty(s)
                    if ~isempty(vecIdx) && strcmp(fieldName, 'y')
                        v = s.y;
                        v(vecIdx) = val;
                        s.y = v;
                    elseif isprop(s, fieldName)
                        s.(fieldName) = val;
                    end
                end
            end
        end

        function val = extractOutput(obj, streamName, fieldStr)
            s = obj.Services.findStream(streamName);
            if isempty(s)
                val = NaN;
                return;
            end
            if strcmp(fieldStr,'n_dot')
                val = s.n_dot;
            elseif strcmp(fieldStr,'T')
                val = s.T;
            elseif strcmp(fieldStr,'P')
                val = s.P;
            else
                tok = regexp(fieldStr,'y\((\d+)\)','tokens');
                if ~isempty(tok)
                    val = s.y(str2double(tok{1}{1}));
                else
                    val = NaN;
                end
            end
        end

        function val = getSensParamValueForApp(obj, paramChoice)
            val = obj.getSensParamValue(paramChoice);
        end
    end

    methods (Access = private)
        function [unitIdx, fieldName, vecIdx, streamName] = parseSensParam(~, paramChoice)
            unitIdx = [];
            fieldName = '';
            vecIdx = [];
            streamName = '';

            tok = regexp(paramChoice, '^Unit \[(\d+)\].*\.\s*(\w+)(?:\((\d+)\))?', 'tokens');
            if ~isempty(tok)
                unitIdx = str2double(tok{1}{1});
                fieldName = tok{1}{2};
                if numel(tok{1}) >= 3 && ~isempty(tok{1}{3})
                    vecIdx = str2double(tok{1}{3});
                end
                return;
            end

            tok = regexp(paramChoice, '^Stream\s+(\S+)\s*\.\s*y\((\d+)\)', 'tokens');
            if ~isempty(tok)
                streamName = tok{1}{1};
                fieldName = 'y';
                vecIdx = str2double(tok{1}{2});
                return;
            end

            tok = regexp(paramChoice, '^Stream\s+(\S+)\s*\.\s*(\w+)', 'tokens');
            if ~isempty(tok)
                streamName = tok{1}{1};
                fieldName = tok{1}{2};
            end
        end

        function val = getSensParamValue(obj, paramChoice)
            val = NaN;
            [unitIdx, fieldName, vecIdx, streamName] = obj.parseSensParam(paramChoice);
            if ~isempty(unitIdx) && unitIdx <= numel(obj.State.units) && ~isempty(fieldName)
                u = obj.State.units{unitIdx};
                if isprop(u, fieldName)
                    try
                        raw = u.(fieldName);
                        if ~isempty(vecIdx)
                            val = raw(vecIdx);
                        else
                            val = raw;
                        end
                    catch
                    end
                end
            elseif ~isempty(streamName) && ~isempty(fieldName)
                s = obj.Services.findStream(streamName);
                if ~isempty(s)
                    if ~isempty(vecIdx) && strcmp(fieldName, 'y')
                        val = s.y(vecIdx);
                    elseif isprop(s, fieldName)
                        val = s.(fieldName);
                    end
                end
            end
        end
    end
end
