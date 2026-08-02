FEATURE_FIELDS = {'RMS','THD','harmMag','harmRatio','phaseShift','timestamp'};

applianceLib = struct();

%  Electric kettle 
applianceLib.Kettle.THD_max        = 5;      % % , resistive -> very low THD
applianceLib.Kettle.H3ratio_max    = 0.05;   % negligible 3rd harmonic
applianceLib.Kettle.phase_max      = 5;      % deg, ~in phase with voltage
applianceLib.Kettle.RMS_min        = 4.0;    % A, kettle draws high current
applianceLib.Kettle.RMS_max        = 8.0;    % A

%  Refrigerator compressor motor
applianceLib.Fridge.THD_range      = [5 20]; % % , moderate distortion
applianceLib.Fridge.H3ratio_range  = [0.05 0.15];
applianceLib.Fridge.phase_min      = 15;     % deg, lagging (inductive)
applianceLib.Fridge.phase_max      = 45;
applianceLib.Fridge.RMS_min        = 1.0;    % A, compressor is lower current
applianceLib.Fridge.RMS_max        = 3.0;

% LED lamp bank  
applianceLib.LEDbank.THD_min       = 20;     % % , driver -> high THD
applianceLib.LEDbank.H3ratio_min   = 0.20;
applianceLib.LEDbank.H5ratio_min   = 0.10;
applianceLib.LEDbank.RMS_min       = 0.1;    % A, low current draw
applianceLib.LEDbank.RMS_max       = 0.6;

%  Laptop charger 
applianceLib.LaptopCharger.THD_min     = 40; % % , rectifier -> very high THD
applianceLib.LaptopCharger.H3ratio_min = 0.30;
applianceLib.LaptopCharger.H5ratio_min = 0.20;
applianceLib.LaptopCharger.RMS_min     = 0.1;
applianceLib.LaptopCharger.RMS_max     = 0.5;

applianceNames = fieldnames(applianceLib); % {'Kettle','Refrigerator compressor motor','LEDbank','LaptopCharger'}

%   RULE-BASED CLASSIFIER FUNCTION

function [status, score] = classifyWindow(features, lib)
    % status: struct with logical ON/OFF per appliance
    % score : struct with fraction of matched sub-rules per appliance
    %         (diagnostic aid while tuning thresholds)

    H1 = features.harmMag(1);
    H3ratio = features.harmRatio(1); % H3/H1
    H5ratio = features.harmRatio(2); % H5/H1
    THD = features.THD;
    RMS = features.RMS;
    phase = features.phaseShift;

    % Kettle 
    rulesKettle = [ ...
        THD <= lib.Kettle.THD_max, ...
        H3ratio <= lib.Kettle.H3ratio_max, ...
        abs(phase) <= lib.Kettle.phase_max, ...
        RMS >= lib.Kettle.RMS_min && RMS <= lib.Kettle.RMS_max ];
    status.Kettle = all(rulesKettle);
    score.Kettle  = mean(rulesKettle);

    % Fridge compressor  
    rulesFridge = [ ...
        THD >= lib.Fridge.THD_range(1) && THD <= lib.Fridge.THD_range(2), ...
        H3ratio >= lib.Fridge.H3ratio_range(1) && H3ratio <= lib.Fridge.H3ratio_range(2), ...
        phase >= lib.Fridge.phase_min && phase <= lib.Fridge.phase_max, ...
        RMS >= lib.Fridge.RMS_min && RMS <= lib.Fridge.RMS_max ];
    status.Fridge = all(rulesFridge);
    score.Fridge  = mean(rulesFridge);

    %  LED lamp bank 
    rulesLED = [ ...
        THD >= lib.LEDbank.THD_min, ...
        H3ratio >= lib.LEDbank.H3ratio_min, ...
        H5ratio >= lib.LEDbank.H5ratio_min, ...
        RMS >= lib.LEDbank.RMS_min && RMS <= lib.LEDbank.RMS_max ];
    status.LEDbank = all(rulesLED);
    score.LEDbank  = mean(rulesLED);

    % Laptop charger 
    rulesCharger = [ ...
        THD >= lib.LaptopCharger.THD_min, ...
        H3ratio >= lib.LaptopCharger.H3ratio_min, ...
        H5ratio >= lib.LaptopCharger.H5ratio_min, ...
        RMS >= lib.LaptopCharger.RMS_min && RMS <= lib.LaptopCharger.RMS_max ];
    status.LaptopCharger = all(rulesCharger);
    score.LaptopCharger  = mean(rulesCharger);
end


%   EVENT-BASED DELTA CLASSIFICATION (for overlapping appliances)

function [eventAppliance, eventType] = classifyDelta(featPrev, featCurr, lib)
    % eventType: 'ON', 'OFF', or 'NONE'
    % eventAppliance: name of appliance matched to the transition, or 'unknown'

    dRMS = featCurr.RMS - featPrev.RMS;
    dH3ratio = featCurr.harmRatio(1) - featPrev.harmRatio(1);
    dTHD = featCurr.THD - featPrev.THD;

    RMS_EVENT_THRESHOLD = 0.05; 

    if abs(dRMS) < RMS_EVENT_THRESHOLD
        eventType = 'NONE';
        eventAppliance = 'none';
        return;
    end

    eventType = 'ON';
    if dRMS < 0
        eventType = 'OFF';
    end

 
    deltaFeat.RMS = abs(dRMS);
    deltaFeat.THD = abs(dTHD);
    deltaFeat.harmRatio = [abs(dH3ratio), featCurr.harmRatio(2)];
    deltaFeat.harmMag = featCurr.harmMag;
    deltaFeat.phaseShift = featCurr.phaseShift;

    [status, score] = classifyWindow(deltaFeat, lib);
    scores = struct2cell(score);
    names = fieldnames(score);
    [~, idx] = max(cell2mat(scores));
    eventAppliance = names{idx};

   
end


%   SLIDING WINDOW DRIVER 



numWindows = 6;
syntheticFeatures = generateSyntheticFeatures(numWindows); % local function below

fprintf('%-10s %-8s %-8s %-10s %-10s %-10s %-10s\n', ...
    'Window','Kettle','Refrigerator compressor motor','LEDbank','Charger','EventType','EventApp');

resultsLog = struct('Kettle',{},'Refrigerator compressor motor',{},'LEDbank',{},'LaptopCharger',{});

for w = 1:numWindows
    feat = syntheticFeatures(w);
    [status, ~] = classifyWindow(feat, applianceLib);
    resultsLog(w) = status;

    if w > 1
        [evApp, evType] = classifyDelta(syntheticFeatures(w-1), feat, applianceLib);
    else
        evApp = 'n/a'; evType = 'n/a';
    end

    fprintf('%-10d %-8d %-8d %-10d %-10d %-10s %-10s\n', ...
        w, status.Kettle, status.Fridge, status.LEDbank, status.LaptopCharger, ...
        evType, evApp);
end

