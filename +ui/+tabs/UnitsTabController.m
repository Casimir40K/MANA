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
            if nargin < 3, editIdx = []; end
            ns = numel(obj.State.speciesNames);
            spStr = strjoin(obj.State.speciesNames, ', ');

            d = uifigure('Name','Reactor (Generic)','Position',[250 180 660 420], ...
                'Resize','off','WindowStyle','modal');
            dg = uigridlayout(d,[8 2],'ColumnWidth',{170,'1x'}, ...
                'RowHeight',repmat({28},1,8),'Padding',[12 12 12 12],'RowSpacing',4);

            uilabel(dg,'Text','Inlet stream:','FontWeight','bold');
            ddIn = uidropdown(dg,'Items',sNames);
            ddIn.Tooltip = 'Feed stream entering the reactor.';
            uilabel(dg,'Text','Outlet stream:','FontWeight','bold');
            ddOut = uidropdown(dg,'Items',sNames);
            ddOut.Tooltip = 'Product stream leaving the reactor.';
            uilabel(dg,'Text','Conversion (0 to 1):','FontWeight','bold');
            efConv = uieditfield(dg,'numeric','Value',0.5,'Limits',[0 1]);
            efConv.Tooltip = 'Fractional conversion of the limiting reactant.';
            lbl = uilabel(dg,'Text',sprintf('Species: %s (1..%d)', spStr, ns));
            lbl.FontColor = [0.4 0.4 0.4];
            uilabel(dg,'Text','');
            uilabel(dg,'Text','Reactant species indices:','FontWeight','bold');
            efReact = uieditfield(dg,'text','Value','1 2');
            efReact.Tooltip = 'Species indices consumed by the reaction.';
            uilabel(dg,'Text','Product species indices:','FontWeight','bold');
            efProd = uieditfield(dg,'text','Value',num2str(ns));
            efProd.Tooltip = 'Species indices produced by the reaction.';
            uilabel(dg,'Text','Stoichiometric coefficients:','FontWeight','bold');
            efStoich = uieditfield(dg,'text','Value',num2str(zeros(1,ns)));
            efStoich.Tooltip = 'One coefficient per species in the shown species order.';

            btnG = uigridlayout(dg,[1 2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0]);
            btnG.Layout.Row = 8;
            btnG.Layout.Column = [1 2];
            uibutton(btnG,'push','Text','OK','FontWeight','bold', ...
                'BackgroundColor',[0.82 0.95 0.82],'ButtonPushedFcn',@(~,~) okCb());
            uibutton(btnG,'push','Text','Cancel','ButtonPushedFcn',@(~,~) delete(d));

            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ddIn.Value = char(string(u.inlet.name));
                ddOut.Value = char(string(u.outlet.name));
                efConv.Value = u.conversion;
                r = u.reactions(1);
                efReact.Value = num2str(r.reactants);
                efProd.Value = num2str(r.products);
                efStoich.Value = num2str(r.stoich);
            elseif numel(sNames) >= 2
                ddOut.Value = sNames{2};
            end

            function okCb()
                rxn.reactants = str2num(efReact.Value); %#ok<ST2NM>
                rxn.products = str2num(efProd.Value); %#ok<ST2NM>
                rxn.stoich = str2num(efStoich.Value); %#ok<ST2NM>
                rxn.name = "reaction";
                if isempty(rxn.reactants) || isempty(rxn.products) || numel(rxn.stoich) ~= ns
                    uialert(d, sprintf('Stoich must have %d entries.', ns), 'Error');
                    return;
                end
                def.type = 'Reactor';
                def.inlet = ddIn.Value;
                def.outlet = ddOut.Value;
                def.conversion = efConv.Value;
                def.reactions = rxn;
                u = proc.units.Reactor(obj.Services.findStream(def.inlet), ...
                    obj.Services.findStream(def.outlet), rxn, efConv.Value);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogLink(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Stream Link', 440, 170, ...
                {{'Inlet:','dropdown',sNames,'Stream entering the link (state is copied to outlet).'}, ...
                 {'Outlet:','dropdown',sNames,'Stream receiving the copied state.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.inlet.name));
                ctrls{2}.Value = char(string(u.outlet.name));
            elseif numel(sNames) >= 2
                ctrls{2}.Value = sNames{2};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type = 'Link';
                def.inlet = ctrls{1}.Value;
                def.outlet = ctrls{2}.Value;
                u = proc.units.Link(obj.Services.findStream(def.inlet), obj.Services.findStream(def.outlet));
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogMixer(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Mixer', 520, 180, ...
                {{'Inlet streams (comma-separated):','text',strjoin(sNames(1:min(2,end)),', '), ...
                  'Streams to combine (e.g. "S1, S2").'}, ...
                 {'Outlet stream:','dropdown',sNames,'Combined outlet stream.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                inN = cellfun(@(s)char(string(s.name)),u.inlets,'Uni',false);
                ctrls{1}.Value = strjoin(inN,', ');
                ctrls{2}.Value = char(string(u.outlet.name));
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                inNms = strtrim(strsplit(ctrls{1}.Value,','));
                inS = {};
                for k = 1:numel(inNms)
                    s = obj.Services.findStream(inNms{k});
                    if isempty(s)
                        uialert(d,sprintf('"%s" not found.',inNms{k}),'Error');
                        return;
                    end
                    inS{end+1} = s; %#ok<AGROW>
                end
                def.type = 'Mixer';
                def.inlets = inNms;
                def.outlet = ctrls{2}.Value;
                u = proc.units.Mixer(inS, obj.Services.findStream(def.outlet));
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogAdjust(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Adjust Controller', 640, 280, ...
                {{'DesignSpec unit index:','numeric',1,'Which DesignSpec unit this controller satisfies.'}, ...
                 {'Manipulated unit index:','numeric',1,'Which unit''s parameter will be varied.'}, ...
                 {'Parameter name:','text','beta','Property to adjust (e.g. beta, conversion, duty).'}, ...
                 {'Parameter index (NaN for scalar):','numeric',NaN,'Use NaN for scalar parameters, or an integer for vector elements.'}, ...
                 {'Minimum value:','numeric',0,'Lower bound for the adjusted parameter.'}, ...
                 {'Maximum value:','numeric',1,'Upper bound for the adjusted parameter.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{3}.Value = u.variableField;
                ctrls{4}.Value = u.variableIndex;
                ctrls{5}.Value = u.minValue;
                ctrls{6}.Value = u.maxValue;
            end
            obj.Services.addDialogButtons(d, @okCb);

            function okCb()
                dsIdx = round(ctrls{1}.Value);
                muIdx = round(ctrls{2}.Value);
                if dsIdx < 1 || dsIdx > numel(obj.State.units) || ~isa(obj.State.units{dsIdx}, 'proc.units.DesignSpec')
                    uialert(d, 'DesignSpec index must refer to an existing DesignSpec unit.', 'Error');
                    return;
                end
                if muIdx < 1 || muIdx > numel(obj.State.units)
                    uialert(d, 'Manipulated unit index invalid.', 'Error');
                    return;
                end
                def = struct('type','Adjust','designSpecIndex',dsIdx,'ownerIndex',muIdx,'field',ctrls{3}.Value, ...
                    'index',ctrls{4}.Value,'minValue',ctrls{5}.Value,'maxValue',ctrls{6}.Value);
                u = proc.units.Adjust(obj.State.units{dsIdx}, obj.State.units{muIdx}, def.field, def.index, def.minValue, def.maxValue);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogDesignSpec(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Design Specification', 620, 230, ...
                {{'Stream to measure:','dropdown',sNames,'Stream whose property is evaluated.'}, ...
                 {'Metric:','dropdown',{'total_flow','comp_flow','mole_fraction'},'Which quantity to track.'}, ...
                 {'Species index:','numeric',1,'Species index (used with comp_flow or mole_fraction).'}, ...
                 {'Target value:','numeric',0.5,'Desired value that the metric should reach.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.stream.name));
                ctrls{2}.Value = u.metric;
                ctrls{3}.Value = u.componentIndex;
                ctrls{4}.Value = u.target;
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def = struct('type','DesignSpec','stream',ctrls{1}.Value,'metric',ctrls{2}.Value, ...
                    'componentIndex',ctrls{3}.Value,'target',ctrls{4}.Value);
                u = proc.units.DesignSpec(obj.Services.findStream(def.stream), def.metric, def.target, def.componentIndex);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogCalculator(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Stream Calculator', 700, 310, ...
                {{'Output stream:','dropdown',sNames,'Stream that receives the result.'}, ...
                 {'Output field:','dropdown',{'n_dot','T','P'},'Which property to set on the output stream.'}, ...
                 {'Input stream A:','dropdown',sNames,'First input stream.'}, ...
                 {'Field A:','dropdown',{'n_dot','T','P'},'Property to read from stream A.'}, ...
                 {'Operator:','dropdown',{'+' '-' '*' '/'},'Arithmetic operator: result = A op B.'}, ...
                 {'Input stream B:','dropdown',sNames,'Second input stream.'}, ...
                 {'Field B:','dropdown',{'n_dot','T','P'},'Property to read from stream B.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.lhsOwner.name));
                ctrls{2}.Value = u.lhsField;
                ctrls{3}.Value = char(string(u.aOwner.name));
                ctrls{4}.Value = u.aField;
                ctrls{5}.Value = u.operator;
                ctrls{6}.Value = char(string(u.bOwner.name));
                ctrls{7}.Value = u.bField;
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def = struct('type','Calculator','lhsStream',ctrls{1}.Value,'lhsField',ctrls{2}.Value, ...
                    'aStream',ctrls{3}.Value,'aField',ctrls{4}.Value,'operator',ctrls{5}.Value, ...
                    'bStream',ctrls{6}.Value,'bField',ctrls{7}.Value);
                u = proc.units.Calculator(obj.Services.findStream(def.lhsStream),def.lhsField, ...
                    obj.Services.findStream(def.aStream),def.aField,def.operator, ...
                    obj.Services.findStream(def.bStream),def.bField);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogConstraint(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Fixed Constraint', 600, 230, ...
                {{'Stream:','dropdown',sNames,'Stream to constrain.'}, ...
                 {'Field:','dropdown',{'n_dot','T','P'},'Property to fix at the given value.'}, ...
                 {'Value:','numeric',1,'Numerical value to enforce.'}, ...
                 {'Index (NaN for scalar):','numeric',NaN,'Use NaN for scalar fields, or an integer for a specific vector element.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.owner.name));
                ctrls{2}.Value = u.field;
                ctrls{3}.Value = u.value;
                ctrls{4}.Value = u.index;
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def = struct('type','Constraint','stream',ctrls{1}.Value,'field',ctrls{2}.Value, ...
                    'value',ctrls{3}.Value,'index',ctrls{4}.Value);
                u = proc.units.Constraint(obj.Services.findStream(def.stream),def.field,def.value,def.index);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogRecycle(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Recycle', 500, 170, ...
                {{'Source stream:','dropdown',sNames,'Computed stream that feeds back.'}, ...
                 {'Tear stream:','dropdown',sNames,'Tear stream for iterative convergence.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.source.name));
                ctrls{2}.Value = char(string(u.tear.name));
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type = 'Recycle';
                def.source = ctrls{1}.Value;
                def.tear = ctrls{2}.Value;
                u = proc.units.Recycle(obj.Services.findStream(def.source), obj.Services.findStream(def.tear));
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogBypass(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Bypass', 660, 310, ...
                {{'Feed stream:','dropdown',sNames,'Incoming stream before the split.'}, ...
                 {'Process inlet:','dropdown',sNames,'Portion sent through the process.'}, ...
                 {'Bypass stream:','dropdown',sNames,'Portion that skips the process.'}, ...
                 {'Process return:','dropdown',sNames,'Processed stream returning for mixing.'}, ...
                 {'Combined outlet:','dropdown',sNames,'Final mixed outlet.'}, ...
                 {'Bypass fraction (0 to 1):','numeric',0.2,'Fraction of feed sent directly to the bypass.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.inlet.name));
                ctrls{2}.Value = char(string(u.processInlet.name));
                ctrls{3}.Value = char(string(u.bypassStream.name));
                ctrls{4}.Value = char(string(u.processReturn.name));
                ctrls{5}.Value = char(string(u.outlet.name));
                ctrls{6}.Value = u.bypassFraction;
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type = 'Bypass';
                def.inlet = ctrls{1}.Value;
                def.processInlet = ctrls{2}.Value;
                def.bypassStream = ctrls{3}.Value;
                def.processReturn = ctrls{4}.Value;
                def.outlet = ctrls{5}.Value;
                def.bypassFraction = ctrls{6}.Value;
                u = proc.units.Bypass(obj.Services.findStream(def.inlet), obj.Services.findStream(def.processInlet), ...
                    obj.Services.findStream(def.bypassStream), obj.Services.findStream(def.processReturn), ...
                    obj.Services.findStream(def.outlet), def.bypassFraction);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogSource(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            ns = numel(obj.State.speciesNames);
            [d, ctrls] = obj.Services.makeDialog('Feed Source', 620, 260, ...
                {{'Outlet stream:','dropdown',sNames,'Stream receiving the feed conditions.'}, ...
                 {'Total flow (NaN = not specified):','numeric',10,'Overall molar flowrate. Use NaN to leave unspecified.'}, ...
                 {sprintf('Mole fractions (%d values, NaN = skip):',ns),'text',num2str(nan(1,ns)),'Composition in species order. Use NaN to leave unspecified.'}, ...
                 {sprintf('Component flows (%d values, NaN = skip):',ns),'text',num2str(nan(1,ns)),'Per-species flowrates in species order. Use NaN to leave unspecified.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.outlet.name));
                ctrls{2}.Value = u.totalFlow;
                ctrls{3}.Value = num2str(u.composition);
                ctrls{4}.Value = num2str(u.componentFlows);
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def = struct();
                def.type = 'Source';
                def.outlet = ctrls{1}.Value;
                def.totalFlow = ctrls{2}.Value;
                def.composition = str2num(ctrls{3}.Value); %#ok<ST2NM>
                def.componentFlows = str2num(ctrls{4}.Value); %#ok<ST2NM>
                opts = struct('totalFlow',def.totalFlow,'composition',def.composition,'componentFlows',def.componentFlows);
                u = proc.units.Source(obj.Services.findStream(def.outlet), opts);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogSink(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Product Sink', 420, 140, ...
                {{'Inlet stream:','dropdown',sNames,'Stream consumed by this sink.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.inlet.name));
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def = struct('type','Sink','inlet',ctrls{1}.Value);
                u = proc.units.Sink(obj.Services.findStream(def.inlet));
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogManifold(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Routing Manifold', 620, 250, ...
                {{'Inlet streams (comma-separated):','text',strjoin(sNames(1:min(2,end)),', '),'Inlet streams (e.g. "S1, S2").'}, ...
                 {'Outlet streams (comma-separated):','text',strjoin(sNames(1:min(2,end)),', '),'Outlet streams to connect (e.g. "S3, S4").'}, ...
                 {'Route vector:','text','1 2','One inlet index per outlet (e.g. "1 2" means outlet 1 gets inlet 1, outlet 2 gets inlet 2).'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                inN = cellfun(@(s)char(string(s.name)),u.inlets,'Uni',false);
                outN = cellfun(@(s)char(string(s.name)),u.outlets,'Uni',false);
                ctrls{1}.Value = strjoin(inN,', ');
                ctrls{2}.Value = strjoin(outN,', ');
                ctrls{3}.Value = num2str(u.route);
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                inNms = strtrim(strsplit(ctrls{1}.Value,','));
                outNms = strtrim(strsplit(ctrls{2}.Value,','));
                route = str2num(ctrls{3}.Value); %#ok<ST2NM>
                if numel(route) ~= numel(outNms)
                    uialert(d,'Route length must equal number of outlets.','Error');
                    return;
                end
                inS = {};
                outS = {};
                for k = 1:numel(inNms)
                    s = obj.Services.findStream(inNms{k});
                    if isempty(s)
                        uialert(d,sprintf('"%s" not found.',inNms{k}),'Error');
                        return;
                    end
                    inS{end+1} = s; %#ok<AGROW>
                end
                for k = 1:numel(outNms)
                    s = obj.Services.findStream(outNms{k});
                    if isempty(s)
                        uialert(d,sprintf('"%s" not found.',outNms{k}),'Error');
                        return;
                    end
                    outS{end+1} = s; %#ok<AGROW>
                end
                def.type = 'Manifold';
                def.inlets = inNms;
                def.outlets = outNms;
                def.route = route;
                u = proc.units.Manifold(inS, outS, route);
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogSplitter(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Flow Splitter', 620, 250, ...
                {{'Feed stream:','dropdown',sNames,'Stream to split into multiple outlets.'}, ...
                 {'Outlet streams (comma-separated):','text',strjoin(sNames(1:min(2,end)),', '),'Outlet stream names (e.g. "S2, S3").'}, ...
                 {'Spec mode:','text','fractions','"fractions" to specify split fractions, or "flows" to specify outlet flowrates.'}, ...
                 {'Values:','text','0.5 0.5','One value per outlet stream, in the same order.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.inlet.name));
                outN = cellfun(@(s)char(string(s.name)),u.outlets,'Uni',false);
                ctrls{2}.Value = strjoin(outN,', ');
                if ~isempty(u.splitFractions)
                    ctrls{3}.Value = 'fractions';
                    ctrls{4}.Value = num2str(u.splitFractions);
                else
                    ctrls{3}.Value = 'flows';
                    ctrls{4}.Value = num2str(u.specifiedOutletFlows);
                end
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                outNms = strtrim(strsplit(ctrls{2}.Value,','));
                outS = {};
                for k = 1:numel(outNms)
                    s = obj.Services.findStream(outNms{k});
                    if isempty(s)
                        uialert(d,sprintf('"%s" not found.',outNms{k}),'Error');
                        return;
                    end
                    outS{end+1} = s; %#ok<AGROW>
                end
                vals = str2num(ctrls{4}.Value); %#ok<ST2NM>
                if numel(vals) ~= numel(outS)
                    uialert(d,'Values length must match number of outlets.','Error');
                    return;
                end
                mode = lower(strtrim(ctrls{3}.Value));
                def.type = 'Splitter';
                def.inlet = ctrls{1}.Value;
                def.outlets = outNms;
                if strcmp(mode,'fractions')
                    def.splitFractions = vals;
                    u = proc.units.Splitter(obj.Services.findStream(def.inlet), outS, 'fractions', vals);
                else
                    def.specifiedOutletFlows = vals;
                    u = proc.units.Splitter(obj.Services.findStream(def.inlet), outS, 'flows', vals);
                end
                obj.Services.commitUnit(u, def, editIdx);
                delete(d);
            end
        end

        function dialogStoichiometricReactor(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            ns = numel(obj.State.speciesNames);
            [d, ctrls] = obj.Services.makeDialog('Stoichiometric Reactor', 620, 280, ...
                {{'Inlet stream:','dropdown',sNames,'Feed stream entering the reactor.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Product stream leaving the reactor.'}, ...
                 {sprintf('Stoichiometric coefficients (%d species):',ns),'text',num2str(zeros(1,ns)),'One value per species in order (negative = consumed, positive = produced).'}, ...
                 {'Extent mode:','text','fixed','"fixed" to specify extent directly, or "solve" to let the solver find it.'}, ...
                 {'Reaction extent:','numeric',0,'Molar extent of reaction (used when mode is "fixed").'}, ...
                 {'Reference species index:','numeric',1,'Species index for sign convention.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.inlet.name));
                ctrls{2}.Value = char(string(u.outlet.name));
                ctrls{3}.Value = num2str(u.nu.');
                ctrls{4}.Value = u.extentMode;
                ctrls{5}.Value = u.extent;
                ctrls{6}.Value = u.referenceSpecies;
            elseif numel(sNames) >= 2
                ctrls{2}.Value = sNames{2};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                nu = str2num(ctrls{3}.Value); %#ok<ST2NM>
                if numel(nu) ~= ns
                    uialert(d,sprintf('Nu vector must have %d entries.',ns),'Error');
                    return;
                end
                def.type='StoichiometricReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.nu=nu; def.extentMode=strtrim(lower(ctrls{4}.Value));
                def.extent=ctrls{5}.Value; def.referenceSpecies=ctrls{6}.Value;
                u=proc.units.StoichiometricReactor(obj.Services.findStream(def.inlet), obj.Services.findStream(def.outlet), def.nu, ...
                    'extent', def.extent, 'extentMode', def.extentMode, 'referenceSpecies', def.referenceSpecies);
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogConversionReactor(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            ns = numel(obj.State.speciesNames);
            [d, ctrls] = obj.Services.makeDialog('Conversion Reactor', 620, 280, ...
                {{'Inlet stream:','dropdown',sNames,'Feed stream entering the reactor.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Product stream leaving the reactor.'}, ...
                 {sprintf('Stoichiometric coefficients (%d species):',ns),'text',num2str(zeros(1,ns)),'One value per species (negative = consumed, positive = produced).'}, ...
                 {'Key species index:','numeric',1,'Conversion is defined relative to this species.'}, ...
                 {'Conversion mode:','text','fixed','"fixed" to specify conversion, or "solve" to let the solver find it.'}, ...
                 {'Conversion (0 to 1):','numeric',0.5,'Fraction of the key species that reacts.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value = char(string(u.inlet.name));
                ctrls{2}.Value = char(string(u.outlet.name));
                ctrls{3}.Value = num2str(u.nu.');
                ctrls{4}.Value = u.keySpecies;
                ctrls{5}.Value = u.conversionMode;
                ctrls{6}.Value = u.conversion;
            elseif numel(sNames) >= 2
                ctrls{2}.Value = sNames{2};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                nu = str2num(ctrls{3}.Value); %#ok<ST2NM>
                if numel(nu) ~= ns
                    uialert(d,sprintf('Nu vector must have %d entries.',ns),'Error');
                    return;
                end
                def.type='ConversionReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.nu=nu; def.keySpecies=ctrls{4}.Value;
                def.conversionMode=strtrim(lower(ctrls{5}.Value)); def.conversion=ctrls{6}.Value;
                u=proc.units.ConversionReactor(obj.Services.findStream(def.inlet), obj.Services.findStream(def.outlet), def.nu, ...
                    def.keySpecies, def.conversion, 'conversionMode', def.conversionMode);
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogYieldReactor(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            [d, ctrls] = obj.Services.makeDialog('Yield Reactor', 640, 300, ...
                {{'Inlet stream:','dropdown',sNames,'Feed stream entering the reactor.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Product stream leaving the reactor.'}, ...
                 {'Basis species index:','numeric',1,'Species consumed; conversion and yields are defined relative to this.'}, ...
                 {'Conversion mode:','text','fixed','"fixed" to specify conversion, or "solve" to let the solver find it.'}, ...
                 {'Conversion (0 to 1):','numeric',0.5,'Fraction of the basis species that reacts.'}, ...
                 {'Product species indices:','text','2','Indices of species produced (space-separated, e.g. "2 3").'}, ...
                 {'Product yields:','text','1','Moles of each product per mole of basis species reacted.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                ctrls{3}.Value=u.basisSpecies;
                ctrls{4}.Value=u.conversionMode;
                ctrls{5}.Value=u.conversion;
                ctrls{6}.Value=num2str(u.productSpecies(:).');
                ctrls{7}.Value=num2str(u.productYields(:).');
            elseif numel(sNames)>=2
                ctrls{2}.Value=sNames{2};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                pIdx = str2num(ctrls{6}.Value); %#ok<ST2NM>
                pY = str2num(ctrls{7}.Value); %#ok<ST2NM>
                if numel(pIdx) ~= numel(pY)
                    uialert(d,'Product indices and yields must have same length.','Error'); return;
                end
                def.type='YieldReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.basisSpecies=ctrls{3}.Value;
                def.conversionMode=strtrim(lower(ctrls{4}.Value)); def.conversion=ctrls{5}.Value;
                def.productSpecies=pIdx; def.productYields=pY;
                u=proc.units.YieldReactor(obj.Services.findStream(def.inlet), obj.Services.findStream(def.outlet), ...
                    def.basisSpecies, def.conversion, def.productSpecies, def.productYields, ...
                    'conversionMode', def.conversionMode);
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogEquilibriumReactor(obj, sNames, editIdx)
            if nargin < 3, editIdx = []; end
            ns = numel(obj.State.speciesNames);
            [d, ctrls] = obj.Services.makeDialog('Equilibrium Reactor', 620, 260, ...
                {{'Inlet stream:','dropdown',sNames,'Feed stream entering the reactor.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Product stream leaving the reactor.'}, ...
                 {sprintf('Stoichiometric coefficients (%d species):',ns),'text',num2str(zeros(1,ns)),'One value per species (negative = consumed, positive = produced).'}, ...
                 {'Equilibrium constant (Keq):','numeric',1,'Equilibrium constant for the reaction.'}, ...
                 {'Reference species index:','numeric',1,'Species index for equilibrium calculation.'}});
            if ~isempty(editIdx)
                u = obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                ctrls{3}.Value=num2str(u.nu.');
                ctrls{4}.Value=u.Keq;
                ctrls{5}.Value=u.referenceSpecies;
            elseif numel(sNames)>=2
                ctrls{2}.Value=sNames{2};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                nu = str2num(ctrls{3}.Value); %#ok<ST2NM>
                if numel(nu) ~= ns
                    uialert(d,sprintf('Nu vector must have %d entries.',ns),'Error'); return;
                end
                def.type='EquilibriumReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.nu=nu; def.Keq=ctrls{4}.Value; def.referenceSpecies=ctrls{5}.Value;
                u=proc.units.EquilibriumReactor(obj.Services.findStream(def.inlet), obj.Services.findStream(def.outlet), ...
                    def.nu, def.Keq, 'referenceSpecies', def.referenceSpecies);
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogHeater(obj, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = obj.Services.makeDialog('Heater', 620, 280, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the heater.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Heated stream leaving the heater.'}, ...
                 {'Thermal spec:','dropdown',{'Tout','duty'},'Set outlet temperature or heat duty.'}, ...
                 {sprintf('Thermal value (%s or %s):', obj.Services.unitLabel('temperature','T'), obj.Services.unitLabel('duty','Q')),'numeric',obj.Services.fromSI(400,'temperature'),'Numerical value for the chosen thermal spec.'}, ...
                 {'Pressure spec:','dropdown',{'pass-through','dP','Pout','PR'},'How to handle outlet pressure.'}, ...
                 {sprintf('Pressure value (%s or ratio):', obj.Services.unitLabel('pressure','P')),'numeric',0,'Value for the chosen pressure spec (ignored for pass-through).'}});
            if ~isempty(editIdx)
                u=obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Tout), ctrls{3}.Value='Tout'; ctrls{4}.Value=obj.Services.fromSI(u.Tout,'temperature');
                else, ctrls{3}.Value='duty'; ctrls{4}.Value=obj.Services.fromSI(u.duty,'duty'); end
                if isprop(u,'dP') && isfinite(u.dP)
                    ctrls{5}.Value='dP'; ctrls{6}.Value=obj.Services.fromSI(u.dP,'pressure');
                elseif isprop(u,'Pout') && isfinite(u.Pout)
                    ctrls{5}.Value='Pout'; ctrls{6}.Value=obj.Services.fromSI(u.Pout,'pressure');
                elseif isprop(u,'PR') && isfinite(u.PR)
                    ctrls{5}.Value='PR'; ctrls{6}.Value=u.PR;
                else
                    ctrls{5}.Value='pass-through'; ctrls{6}.Value=0;
                end
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Heater'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                tMode=ctrls{3}.Value; tVal=ctrls{4}.Value;
                if ~isfinite(tVal), uialert(d,'Thermal value must be finite.','Error'); return; end
                if strcmp(tMode,'Tout'), def.Tout=obj.Services.toSI(tVal,'temperature'); else, def.duty=obj.Services.toSI(tVal,'duty'); end
                pMode=ctrls{5}.Value; pVal=ctrls{6}.Value;
                if ~strcmp(pMode,'pass-through') && ~isfinite(pVal)
                    uialert(d,'Pressure value must be finite for selected pressure mode.','Error'); return;
                end
                if strcmp(pMode,'dP')
                    def.dP = obj.Services.toSI(pVal,'pressure');
                elseif strcmp(pMode,'Pout')
                    prefs = obj.Services.getUnitPrefs();
                    if pVal <= 0, uialert(d,sprintf('Pout must be > 0 %s.', prefs.pressure),'Error'); return; end
                    def.Pout = obj.Services.toSI(pVal,'pressure');
                elseif strcmp(pMode,'PR')
                    if pVal <= 0, uialert(d,'PR must be > 0.','Error'); return; end
                    def.PR = pVal;
                end
                pCount = double(isfield(def,'dP')) + double(isfield(def,'Pout')) + double(isfield(def,'PR'));
                if pCount > 1
                    uialert(d,'Select only one pressure mode (dP, Pout, or PR).','Error'); return;
                end
                mix = obj.Services.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Heater(obj.Services.findStream(def.inlet),obj.Services.findStream(def.outlet),mix,args{:});
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogCooler(obj, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = obj.Services.makeDialog('Cooler', 620, 280, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the cooler.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Cooled stream leaving the cooler.'}, ...
                 {'Thermal spec:','dropdown',{'Tout','duty'},'Set outlet temperature or heat duty.'}, ...
                 {sprintf('Thermal value (%s or %s):', obj.Services.unitLabel('temperature','T'), obj.Services.unitLabel('duty','Q')),'numeric',obj.Services.fromSI(300,'temperature'),'Numerical value for the chosen thermal spec.'}, ...
                 {'Pressure spec:','dropdown',{'pass-through','dP','Pout','PR'},'How to handle outlet pressure.'}, ...
                 {sprintf('Pressure value (%s or ratio):', obj.Services.unitLabel('pressure','P')),'numeric',0,'Value for the chosen pressure spec (ignored for pass-through).'}});
            if ~isempty(editIdx)
                u=obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Tout), ctrls{3}.Value='Tout'; ctrls{4}.Value=obj.Services.fromSI(u.Tout,'temperature');
                else, ctrls{3}.Value='duty'; ctrls{4}.Value=obj.Services.fromSI(u.duty,'duty'); end
                if isprop(u,'dP') && isfinite(u.dP)
                    ctrls{5}.Value='dP'; ctrls{6}.Value=obj.Services.fromSI(u.dP,'pressure');
                elseif isprop(u,'Pout') && isfinite(u.Pout)
                    ctrls{5}.Value='Pout'; ctrls{6}.Value=obj.Services.fromSI(u.Pout,'pressure');
                elseif isprop(u,'PR') && isfinite(u.PR)
                    ctrls{5}.Value='PR'; ctrls{6}.Value=u.PR;
                else
                    ctrls{5}.Value='pass-through'; ctrls{6}.Value=0;
                end
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Cooler'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                tMode=ctrls{3}.Value; tVal=ctrls{4}.Value;
                if ~isfinite(tVal), uialert(d,'Thermal value must be finite.','Error'); return; end
                if strcmp(tMode,'Tout'), def.Tout=obj.Services.toSI(tVal,'temperature'); else, def.duty=obj.Services.toSI(tVal,'duty'); end
                pMode=ctrls{5}.Value; pVal=ctrls{6}.Value;
                if ~strcmp(pMode,'pass-through') && ~isfinite(pVal)
                    uialert(d,'Pressure value must be finite for selected pressure mode.','Error'); return;
                end
                if strcmp(pMode,'dP')
                    def.dP = obj.Services.toSI(pVal,'pressure');
                elseif strcmp(pMode,'Pout')
                    prefs = obj.Services.getUnitPrefs();
                    if pVal <= 0, uialert(d,sprintf('Pout must be > 0 %s.', prefs.pressure),'Error'); return; end
                    def.Pout = obj.Services.toSI(pVal,'pressure');
                elseif strcmp(pMode,'PR')
                    if pVal <= 0, uialert(d,'PR must be > 0.','Error'); return; end
                    def.PR = pVal;
                end
                pCount = double(isfield(def,'dP')) + double(isfield(def,'Pout')) + double(isfield(def,'PR'));
                if pCount > 1
                    uialert(d,'Select only one pressure mode (dP, Pout, or PR).','Error'); return;
                end
                mix = obj.Services.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Cooler(obj.Services.findStream(def.inlet),obj.Services.findStream(def.outlet),mix,args{:});
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogPurge(obj, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = obj.Services.makeDialog('Purge Split', 560, 230, ...
                {{'Feed stream:','dropdown',sNames,'Stream to split into recycle and purge.'}, ...
                 {'Recycle stream:','dropdown',sNames,'Stream returned to the loop.'}, ...
                 {'Purge stream:','dropdown',sNames,'Bleed stream removed from the loop.'}, ...
                 {'Recycle fraction (0 to 1):','numeric',0.9,'Fraction of feed sent to recycle. Remainder goes to purge.'}});
            if ~isempty(editIdx)
                u=obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.recycle.name));
                ctrls{3}.Value=char(string(u.purge.name));
                ctrls{4}.Value=u.beta;
            elseif numel(sNames)>=3
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Purge'; def.inlet=ctrls{1}.Value;
                def.recycle=ctrls{2}.Value; def.purge=ctrls{3}.Value;
                def.beta=ctrls{4}.Value;
                u=proc.units.Purge(obj.Services.findStream(def.inlet),...
                    obj.Services.findStream(def.recycle),obj.Services.findStream(def.purge),def.beta);
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogHeatExchanger(obj, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = obj.Services.makeDialog('Heat Exchanger', 650, 300, ...
                {{'Hot inlet:','dropdown',sNames,'Hot stream entering the exchanger.'}, ...
                 {'Hot outlet:','dropdown',sNames,'Hot stream leaving the exchanger.'}, ...
                 {'Cold inlet:','dropdown',sNames,'Cold stream entering the exchanger.'}, ...
                 {'Cold outlet:','dropdown',sNames,'Cold stream leaving the exchanger.'}, ...
                 {'Spec mode:','dropdown',{'Th_out','Tc_out','duty'},'Specify hot outlet T, cold outlet T, or heat duty.'}, ...
                 {sprintf('Spec value (%s or %s):', obj.Services.unitLabel('temperature','T'), obj.Services.unitLabel('duty','Q')),'numeric',obj.Services.fromSI(350,'temperature'),'Value for the chosen specification.'}});
            if ~isempty(editIdx)
                u=obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.hotInlet.name));
                ctrls{2}.Value=char(string(u.hotOutlet.name));
                ctrls{3}.Value=char(string(u.coldInlet.name));
                ctrls{4}.Value=char(string(u.coldOutlet.name));
                if isfinite(u.Th_out), ctrls{5}.Value='Th_out'; ctrls{6}.Value=obj.Services.fromSI(u.Th_out,'temperature');
                elseif isfinite(u.Tc_out), ctrls{5}.Value='Tc_out'; ctrls{6}.Value=obj.Services.fromSI(u.Tc_out,'temperature');
                else, ctrls{5}.Value='duty'; ctrls{6}.Value=obj.Services.fromSI(u.duty,'duty'); end
            elseif numel(sNames)>=4
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3}; ctrls{4}.Value=sNames{4};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type='HeatExchanger';
                def.hotInlet=ctrls{1}.Value; def.hotOutlet=ctrls{2}.Value;
                def.coldInlet=ctrls{3}.Value; def.coldOutlet=ctrls{4}.Value;
                mode=ctrls{5}.Value; val=ctrls{6}.Value;
                if strcmp(mode,'Th_out'), def.Th_out=obj.Services.toSI(val,'temperature');
                elseif strcmp(mode,'Tc_out'), def.Tc_out=obj.Services.toSI(val,'temperature');
                else, def.duty=obj.Services.toSI(val,'duty'); end
                mix = obj.Services.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Th_out'), args=[args,{'Th_out',def.Th_out}]; end
                if isfield(def,'Tc_out'), args=[args,{'Tc_out',def.Tc_out}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                u=proc.units.HeatExchanger(obj.Services.findStream(def.hotInlet),obj.Services.findStream(def.hotOutlet),...
                    obj.Services.findStream(def.coldInlet),obj.Services.findStream(def.coldOutlet),mix,args{:});
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogCompressor(obj, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = obj.Services.makeDialog('Compressor', 560, 240, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the compressor.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Compressed stream leaving the compressor.'}, ...
                 {'Pressure spec:','dropdown',{'Pout','PR'},'Set outlet pressure or pressure ratio.'}, ...
                 {sprintf('Pressure value (%s or ratio):', obj.Services.unitLabel('pressure','P')),'numeric',obj.Services.fromSI(2e5,'pressure'),'Numerical value for the chosen pressure spec.'}, ...
                 {'Isentropic efficiency (0 to 1):','numeric',0.85,'Compressor isentropic efficiency.'}});
            if ~isempty(editIdx)
                u=obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Pout), ctrls{3}.Value='Pout'; ctrls{4}.Value=obj.Services.fromSI(u.Pout,'pressure');
                else, ctrls{3}.Value='PR'; ctrls{4}.Value=u.PR; end
                ctrls{5}.Value=u.eta;
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Compressor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                mode=ctrls{3}.Value; val=ctrls{4}.Value;
                if strcmp(mode,'Pout'), def.Pout=obj.Services.toSI(val,'pressure'); else, def.PR=val; end
                def.eta=ctrls{5}.Value;
                mix = obj.Services.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {'eta', def.eta};
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Compressor(obj.Services.findStream(def.inlet),obj.Services.findStream(def.outlet),mix,args{:});
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogTurbine(obj, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = obj.Services.makeDialog('Turbine', 560, 240, ...
                {{'Inlet stream:','dropdown',sNames,'Stream entering the turbine.'}, ...
                 {'Outlet stream:','dropdown',sNames,'Expanded stream leaving the turbine.'}, ...
                 {'Pressure spec:','dropdown',{'Pout','PR'},'Set outlet pressure or pressure ratio.'}, ...
                 {sprintf('Pressure value (%s or ratio):', obj.Services.unitLabel('pressure','P')),'numeric',obj.Services.fromSI(5e4,'pressure'),'Numerical value for the chosen pressure spec.'}, ...
                 {'Isentropic efficiency (0 to 1):','numeric',0.85,'Turbine isentropic efficiency.'}});
            if ~isempty(editIdx)
                u=obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Pout), ctrls{3}.Value='Pout'; ctrls{4}.Value=obj.Services.fromSI(u.Pout,'pressure');
                else, ctrls{3}.Value='PR'; ctrls{4}.Value=u.PR; end
                ctrls{5}.Value=u.eta;
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Turbine'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                mode=ctrls{3}.Value; val=ctrls{4}.Value;
                if strcmp(mode,'Pout'), def.Pout=obj.Services.toSI(val,'pressure'); else, def.PR=val; end
                def.eta=ctrls{5}.Value;
                mix = obj.Services.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {'eta', def.eta};
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Turbine(obj.Services.findStream(def.inlet),obj.Services.findStream(def.outlet),mix,args{:});
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogSeparator(obj, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(obj.State.speciesNames);
            [d, ctrls] = obj.Services.makeDialog('Separator', 620, 240, ...
                {{'Feed stream:','dropdown',sNames,'Stream entering the separator.'}, ...
                 {'Outlet A:','dropdown',sNames,'First outlet stream.'}, ...
                 {'Outlet B:','dropdown',sNames,'Second outlet stream (remainder).'}, ...
                 {sprintf('Split fractions to A (%d species):',ns),'text',num2str(repmat(0.5,1,ns)),'Fraction of each species sent to outlet A (0 to 1). Remainder goes to B.'}});
            if ~isempty(editIdx)
                u=obj.State.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outletA.name));
                ctrls{3}.Value=char(string(u.outletB.name));
                ctrls{4}.Value=num2str(u.phi);
            elseif numel(sNames)>=3
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3};
            end
            obj.Services.addDialogButtons(d, @okCb);
            function okCb()
                phi=str2num(ctrls{4}.Value); %#ok<ST2NM>
                if numel(phi)~=ns
                    uialert(d,sprintf('phi needs %d values.',ns),'Error'); return;
                end
                def.type='Separator'; def.inlet=ctrls{1}.Value;
                def.outletA=ctrls{2}.Value; def.outletB=ctrls{3}.Value; def.phi=phi;
                u=proc.units.Separator(obj.Services.findStream(def.inlet),...
                    obj.Services.findStream(def.outletA),obj.Services.findStream(def.outletB),phi);
                obj.Services.commitUnit(u,def,editIdx); delete(d);
            end
        end
    end
end
