function [lib, templates] = applianceLibrary(params)
%APPLIANCELIBRARY Known harmonic signatures of the four modelled appliances.
%
%   [lib, templates] = APPLIANCELIBRARY(params)
%
%   This is the classifier's reference book. For each appliance it holds the
%   expected complex harmonic phasor at every analysis order, built from the
%   same numbers used to generate the signals in model_four_appliances.m.
%
%   IMPORTANT: these values MIRROR model_four_appliances.m. If Joseph or
%   Edmund change an appliance definition there, the same change must be made
%   here or the classifier will be matching against the wrong templates. The
%   duplication is deliberate - it keeps the classifier usable on a blind
%   recording, where no simulation struct exists to read the values from.
%
%   INPUTS
%     params : project parameter struct. Uses f0 and analysisHarmonics.
%
%   OUTPUTS
%     lib       : 1 x A struct array, one entry per appliance, carrying the
%                 physical description and the rule-based thresholds
%     templates : A x K complex matrix. Row a, column k is the phasor that
%                 appliance a contributes at analysis harmonic k, in peak
%                 amperes. This is what classifyLoad matches against.
%
%   HOW A TEMPLATE IS BUILT
%     Each appliance is defined by a fundamental RMS current, a fundamental
%     phase angle, and a table of [order, magnitude ratio, phase]. The peak
%     amplitude at harmonic k is sqrt(2) * RMS * ratio(k), and its phase is
%     taken straight from the table. Together they give a complex phasor
%     A*exp(j*phi), which is exactly what extractHarmonicPhasors measures
%     from a real window - so the two can be compared directly.
%
%   See also CLASSIFYLOAD, MODEL_FOUR_APPLIANCES, EXTRACTHARMONICPHASORS.

    if nargin < 1
        params = struct();
    end

    orders = getParam(params, 'analysisHarmonics', 1:2:15);
    orders = orders(:).';

    % =====================================================================
    % Appliance definitions - mirror of model_four_appliances.m
    % Harmonic table columns: [order, magnitude ratio, phase in degrees]
    % =====================================================================

    lib = struct([]);

    lib(1).name = 'Kettle';
    lib(1).fullName = 'Electric Kettle / Resistive Heater';
    lib(1).loadType = 'Resistive heating load';
    lib(1).fundamentalRMS_A = 6.0;
    lib(1).fundamentalPhase_deg = 0;
    lib(1).harmonics = [ 1  1.00    0; ...
                         3  0.020  20; ...
                         5  0.010 -35];
    lib(1).signature = 'Large fundamental, almost no harmonics, current in phase with voltage';

    lib(2).name = 'Refrigerator';
    lib(2).fullName = 'Refrigerator Compressor Motor';
    lib(2).loadType = 'Inductive motor load';
    lib(2).fundamentalRMS_A = 2.0;
    lib(2).fundamentalPhase_deg = -35;
    lib(2).harmonics = [ 1  1.00  -35; ...
                         3  0.080 -80; ...
                         5  0.050 110; ...
                         7  0.025  40];
    lib(2).signature = 'Lagging phase angle plus a start-up inrush';

    lib(3).name = 'LEDbank';
    lib(3).fullName = 'LED Lamp Bank / Rectifier Driver';
    lib(3).loadType = 'Nonlinear rectifier lighting load';
    lib(3).fundamentalRMS_A = 0.7;
    lib(3).fundamentalPhase_deg = 5;
    lib(3).harmonics = [ 1   1.00   5; ...
                         3   0.55 -10; ...
                         5   0.35  60; ...
                         7   0.22 -50; ...
                         9   0.14  20; ...
                        11   0.10 -90];
    lib(3).signature = 'Dominant 3rd harmonic, strong odd harmonics, low current';

    lib(4).name = 'LaptopCharger';
    lib(4).fullName = 'Laptop Charger / Switch-Mode Power Supply';
    lib(4).loadType = 'Switch-mode power supply load';
    lib(4).fundamentalRMS_A = 1.1;
    lib(4).fundamentalPhase_deg = 18;
    lib(4).harmonics = [ 1   1.00   18; ...
                         3   0.25  -40; ...
                         5   0.50   70; ...
                         7   0.40 -110; ...
                        11   0.26  130; ...
                        13   0.18  -70; ...
                        15   0.10   30];
    lib(4).signature = 'Fifth and seventh harmonics exceed the third, content up to the 15th';

    numAppliances = numel(lib);

    % =====================================================================
    % Rule-based thresholds
    %
    % These are DERIVED from the definitions above, not guessed, so that the
    % report can show where every number came from. For each appliance the
    % expected THD is computed directly from its own harmonic table:
    %
    %     THD = 100 * sqrt(sum of squared harmonic ratios) / 1.00
    %
    % and the thresholds are placed at a tolerance either side of it. The
    % default tolerance is generous because a window containing several
    % appliances shows a blend of their signatures, not any one of them.
    % =====================================================================

    ruleTolerance = getParam(params, 'ruleTolerance', 0.5);   % +/- 50 percent

    for a = 1:numAppliances

        H = lib(a).harmonics;

        ratios = H(:, 2);
        isFundamental = (H(:, 1) == 1);

        expectedTHD = 100 * sqrt(sum(ratios(~isFundamental).^2)) / ratios(isFundamental);

        lib(a).expectedTHD_percent = expectedTHD;
        lib(a).THD_min = expectedTHD * (1 - ruleTolerance);
        lib(a).THD_max = expectedTHD * (1 + ruleTolerance);

        lib(a).expectedRMS_A = lib(a).fundamentalRMS_A * sqrt(sum(ratios.^2));
        lib(a).RMS_min = lib(a).expectedRMS_A * (1 - ruleTolerance);
        lib(a).RMS_max = lib(a).expectedRMS_A * (1 + ruleTolerance);

        lib(a).expectedH3 = ratioAtOrder(H, 3);
        lib(a).expectedH5 = ratioAtOrder(H, 5);
        lib(a).expectedH7 = ratioAtOrder(H, 7);

        % Phase convention: NEGATIVE means the current lags the voltage,
        % which is what an inductive load does. The original rule expected
        % the refrigerator between +15 and +45 degrees and could therefore
        % never fire, because the model gives it -35 degrees.
        lib(a).expectedPhase_deg = lib(a).fundamentalPhase_deg;
        lib(a).phase_min = lib(a).fundamentalPhase_deg - 20;
        lib(a).phase_max = lib(a).fundamentalPhase_deg + 20;

    end

    % =====================================================================
    % Build the phasor templates at the analysis harmonics
    % =====================================================================

    K = numel(orders);
    templates = zeros(numAppliances, K);

    for a = 1:numAppliances

        H = lib(a).harmonics;
        peakFundamental = sqrt(2) * lib(a).fundamentalRMS_A;

        for k = 1:K

            row = find(H(:, 1) == orders(k), 1);

            if isempty(row)
                templates(a, k) = 0;      % appliance has no content at this order
            else
                amplitude = peakFundamental * H(row, 2);
                phaseRad = H(row, 3) * pi/180;
                templates(a, k) = amplitude * exp(1i * phaseRad);
            end

        end

        lib(a).template = templates(a, :);

    end

    % Attach the shared metadata to every entry so a single element carries
    % enough context to be interpreted on its own.
    for a = 1:numAppliances
        lib(a).analysisHarmonics = orders;
        lib(a).f0_Hz = getParam(params, 'f0', 50);
        lib(a).units = 'peak amperes';
    end

end

% =========================================================================
% Helper: magnitude ratio at a given harmonic order, 0 if absent
% =========================================================================
function ratio = ratioAtOrder(harmonicTable, wantedOrder)

    row = find(harmonicTable(:, 1) == wantedOrder, 1);

    if isempty(row)
        ratio = 0;
    else
        ratio = harmonicTable(row, 2);
    end

end

% =========================================================================
% Helper: read an optional parameter with a default
% =========================================================================
function value = getParam(params, name, defaultValue)

    if isfield(params, name) && ~isempty(params.(name))
        value = params.(name);
    else
        value = defaultValue;
    end

end
