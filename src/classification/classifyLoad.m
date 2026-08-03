function [predictions, predictionMatrix] = classifyLoad(features)
%CLASSIFYLOAD Rule-based appliance classifier.
%
% INPUT:
%   features - Struct array returned by extractFeatures.m
%
% OUTPUT:
%   predictions - Struct array containing ON/OFF predictions for each
%   appliance together with detected events.

    applianceLib = createApplianceLibrary();

    requiredFields = {'RMS','THD','harmMag','harmRatio','phaseShift'};

    for i = 1:numel(requiredFields)
        if ~isfield(features, requiredFields{i})
            error("Missing feature field: %s", requiredFields{i});
        end
    end

    numWindows = numel(features);

    predictions = repmat(struct(), numWindows, 1);
    predictionMatrix = false(numWindows,4);

    for k = 1:numWindows

        [status, ~] = classifyWindow(features(k), applianceLib);

        predictions(k) = status;
        predictionMatrix(k,:) = [ ...
            status.Kettle,...
            status.Refrigerator,...
            status.LEDbank,...
            status.LaptopCharger];

        if k > 1

            [predictions(k).eventAppliance,...
             predictions(k).eventType] = ...
                classifyDelta(features(k-1),features(k),applianceLib);

        else

            predictions(k).eventAppliance = "none";
            predictions(k).eventType = "NONE";

        end

    end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function applianceLib = createApplianceLibrary()

    applianceLib = struct();

    %% KETTLE

    applianceLib.Kettle.THD_max = 5;
    applianceLib.Kettle.H3ratio_max = 0.05;
    applianceLib.Kettle.phase_max = 5;
    applianceLib.Kettle.RMS_min = 4.0;
    applianceLib.Kettle.RMS_max = 8.0;

   %% REFRIGERATOR COMPRESSOR

    applianceLib.Refrigerator.THD_range = [5 20];
    applianceLib.Refrigerator.H3ratio_range = [0.05 0.15];
    applianceLib.Refrigerator.phase_min = 15;
    applianceLib.Refrigerator.phase_max = 45;
    applianceLib.Refrigerator.RMS_min = 1.0;
    applianceLib.Refrigerator.RMS_max = 3.0;

    %% LED

    applianceLib.LEDbank.THD_min = 20;
    applianceLib.LEDbank.H3ratio_min = 0.20;
    applianceLib.LEDbank.H5ratio_min = 0.10;
    applianceLib.LEDbank.RMS_min = 0.10;
    applianceLib.LEDbank.RMS_max = 0.60;

    %% LAPTOP CHARGER

    applianceLib.LaptopCharger.THD_min = 40;
    applianceLib.LaptopCharger.H3ratio_min = 0.30;
    applianceLib.LaptopCharger.H5ratio_min = 0.20;
    applianceLib.LaptopCharger.RMS_min = 0.10;
    applianceLib.LaptopCharger.RMS_max = 0.50;

end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [status, score] = classifyWindow(features, lib)

    THD   = features.THD;
    RMS   = features.RMS;
    phase = features.phaseShift;

    % Safely extract harmonic ratios
    H3ratio = 0;
    H5ratio = 0;

    if ~isempty(features.harmRatio)
        H3ratio = features.harmRatio(1);
    end

    if numel(features.harmRatio) >= 2
        H5ratio = features.harmRatio(2);
    end

    %% KETTLE

    rulesKettle = [ ...
        THD <= lib.Kettle.THD_max,...
        H3ratio <= lib.Kettle.H3ratio_max,...
        abs(phase) <= lib.Kettle.phase_max,...
        RMS >= lib.Kettle.RMS_min && ...
        RMS <= lib.Kettle.RMS_max];

    status.Kettle = all(rulesKettle);
    score.Kettle  = mean(rulesKettle);

    %% REFRIGERATOR COMPRESSOR

    rulesRefrigerator = [ ...
        THD >= lib.Refrigerator.THD_range(1) && ...
        THD <= lib.Refrigerator.THD_range(2),...
        H3ratio >= lib.Refrigerator.H3ratio_range(1) && ...
        H3ratio <= lib.Refrigerator.H3ratio_range(2),...
        phase >= lib.Refrigerator.phase_min && ...
        phase <= lib.Refrigerator.phase_max,...
        RMS >= lib.Refrigerator.RMS_min && ...
        RMS <= lib.Refrigerator.RMS_max];
    
    status.Refrigerator = all(rulesRefrigerator);
    score.Refrigerator = mean(rulesRefrigerator);

    %% LED BANK

    rulesLED = [ ...
        THD >= lib.LEDbank.THD_min,...
        H3ratio >= lib.LEDbank.H3ratio_min,...
        H5ratio >= lib.LEDbank.H5ratio_min,...
        RMS >= lib.LEDbank.RMS_min && ...
        RMS <= lib.LEDbank.RMS_max];

    status.LEDbank = all(rulesLED);
    score.LEDbank  = mean(rulesLED);

    %% LAPTOP CHARGER

    rulesCharger = [ ...
        THD >= lib.LaptopCharger.THD_min,...
        H3ratio >= lib.LaptopCharger.H3ratio_min,...
        H5ratio >= lib.LaptopCharger.H5ratio_min,...
        RMS >= lib.LaptopCharger.RMS_min && ...
        RMS <= lib.LaptopCharger.RMS_max];

    status.LaptopCharger = all(rulesCharger);
    score.LaptopCharger  = mean(rulesCharger);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [eventAppliance, eventType] = classifyDelta(featPrev, featCurr, lib)

    dRMS = featCurr.RMS - featPrev.RMS;
    dTHD = featCurr.THD - featPrev.THD;

    H3prev = 0;
    H3curr = 0;

    if ~isempty(featPrev.harmRatio)
        H3prev = featPrev.harmRatio(1);
    end

    if ~isempty(featCurr.harmRatio)
        H3curr = featCurr.harmRatio(1);
    end

    dH3ratio = H3curr - H3prev;

    RMS_EVENT_THRESHOLD = 0.05;

    if abs(dRMS) < RMS_EVENT_THRESHOLD
        eventType = "NONE";
        eventAppliance = "none";
        return;
    end

    if dRMS > 0
        eventType = "ON";
    else
        eventType = "OFF";
    end

    deltaFeat = struct();

    deltaFeat.RMS = abs(dRMS);
    deltaFeat.THD = abs(dTHD);

    H5curr = 0;
    if numel(featCurr.harmRatio) >= 2
        H5curr = featCurr.harmRatio(2);
    end

    deltaFeat.harmRatio = [abs(dH3ratio), H5curr];
    deltaFeat.harmMag = featCurr.harmMag;
    deltaFeat.phaseShift = featCurr.phaseShift;

    [~, score] = classifyWindow(deltaFeat, lib);

    scores = struct2cell(score);
    names = fieldnames(score);

    [~, idx] = max(cell2mat(scores));

    eventAppliance = names{idx};

end