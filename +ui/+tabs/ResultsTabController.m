classdef ResultsTabController < handle
    properties
        State
        Services struct
    end

    methods
        function obj = ResultsTabController(state, services)
            obj.State = state;
            obj.Services = services;
        end

        function refreshResultsTable(obj)
            obj.Services.refreshResultsTable();
        end

        function refreshResultsSummaryModel(obj)
            obj.Services.refreshResultsSummaryModel();
        end

        function refreshResultsSummaryPanel(obj)
            obj.Services.refreshResultsSummaryPanel();
        end

        function refreshResultsTablesTab(obj)
            obj.Services.refreshResultsTablesTab();
        end
    end
end
