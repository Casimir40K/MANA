classdef UnitsTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = UnitsTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function dialogReactor(obj, sNames, editIdx)
            obj.Services.dialogReactor(sNames, editIdx);
        end

        function dialogAdjust(obj, sNames, editIdx)
            obj.Services.dialogAdjust(sNames, editIdx);
        end
    end
end
