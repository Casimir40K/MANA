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

        function onStreamValEdit(obj, src, evt)
            obj.Services.onStreamValEdit(src, evt);
        end

        function onKnownEdit(obj, src, evt)
            obj.Services.onKnownEdit(src, evt);
        end

        function addStreamFromUI(obj)
            obj.Services.addStreamFromUI();
        end

        function removeSelectedStream(obj)
            obj.Services.removeSelectedStream();
        end
    end
end
