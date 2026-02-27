classdef StreamsTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = StreamsTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function addStreamFromUI(obj)
            name = strtrim(obj.Services.getNewStreamName());
            if isempty(name)
                obj.Services.alertError('Enter a name.');
                return;
            end
            for i = 1:numel(obj.State.streams)
                if strcmp(string(obj.State.streams{i}.name), name)
                    obj.Services.alertWithTitle(sprintf('"%s" exists.', name), 'Duplicate');
                    return;
                end
            end

            obj.Services.addStreamInternal(name);
            obj.Services.refreshStreamTables();
            obj.Services.updateDOF();
            obj.Services.updateSensDropdowns();

            tok = regexp(name, '^([A-Za-z_]*)(\d+)$', 'tokens');
            if ~isempty(tok)
                obj.Services.setNextStreamName(sprintf('%s%d', tok{1}{1}, str2double(tok{1}{2}) + 1));
            end
        end

        function removeSelectedStream(obj)
            row = obj.Services.getSelectedStreamRow();
            if isempty(row), return; end
            if row >= 1 && row <= numel(obj.State.streams)
                obj.State.streams(row) = [];
                obj.Services.refreshStreamTables();
                obj.Services.updateDOF();
                obj.Services.updateSensDropdowns();
            end
        end

        function onStreamValEdit(obj, ~, evt)
            row = evt.Indices(1);
            col = evt.Indices(2);
            if row < 1 || row > numel(obj.State.streams), return; end
            s = obj.State.streams{row};
            ns = numel(obj.State.speciesNames);
            switch col
                case 2
                    s.n_dot = obj.Services.toSI(evt.NewData, 'flow');
                case 3
                    s.T = obj.Services.toSI(evt.NewData, 'temperature');
                case 4
                    s.P = obj.Services.toSI(evt.NewData, 'pressure');
                otherwise
                    j = col - 4;
                    if j >= 1 && j <= ns
                        s.y(j) = evt.NewData;
                    end
            end
            obj.Services.refreshStreamTables();
        end

        function onKnownEdit(obj, ~, evt)
            row = evt.Indices(1);
            col = evt.Indices(2);
            if row < 1 || row > numel(obj.State.streams), return; end
            s = obj.State.streams{row};
            val = logical(evt.NewData);
            switch col
                case 2
                    s.known.n_dot = val;
                case 3
                    s.known.T = val;
                case 4
                    s.known.P = val;
                case 5
                    s.known.y(:) = val;
            end
            obj.Services.updateDOF();
        end
    end
end
