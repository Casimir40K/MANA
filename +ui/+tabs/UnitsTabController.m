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
    end
end
