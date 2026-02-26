classdef AppState < handle
    %APPSTATE Lightweight shared application state.
    properties
        speciesNames cell = {'H2','O2','H2O'}
        speciesMW double = [2.016, 32.00, 18.015]
        streams cell = {}
        units cell = {}
        unitDefs cell = {}
        lastSolver = []
        lastFlowsheet = []
        metadata struct = struct( ...
            'projectTitle', 'MathLab_Project', ...
            'unitPrefs', struct('flow','kmol/s','temperature','K','pressure','Pa','duty','kW','power','kW'), ...
            'lastExportPath', '')
    end
end
