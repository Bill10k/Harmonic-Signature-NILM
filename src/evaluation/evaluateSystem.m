function results = evaluateSystem(trueStates, predStates, applianceNames, options)
%EVALUATESYSTEM Scores the classifier against ground truth.
%
%   results = EVALUATESYSTEM(trueStates, predStates)
%   results = EVALUATESYSTEM(trueStates, predStates, applianceNames)
%   results = EVALUATESYSTEM(trueStates, predStates, applianceNames, options)
%
%   Computes the Key Performance Metric this project is graded on:
%   overall classification accuracy and macro-F1 of appliance ON/OFF state.
%
%   INPUTS
%     trueStates     : numWindows x numAppliances logical, ground truth
%                      (sim.windowStates from model_four_appliances)
%     predStates     : numWindows x numAppliances logical, predictions
%                      (second output of classifyLoad)
%     applianceNames : optional 1 x numAppliances cell array of names
%     options        : optional struct
%                        verbose   print the tables   [default true]
%                        label     text for the header [default 'Evaluation']
%
%   OUTPUT
%     results : struct containing
%                 accuracy         overall per-decision accuracy (the KPM)
%                 macroF1          unweighted mean F1 across appliances (the KPM)
%                 microF1          F1 pooled over all decisions
%                 exactMatch       fraction of windows where ALL four were right
%                 hammingLoss      fraction of individual decisions that were wrong
%                 perAppliance     struct array of per-appliance metrics
%                 confusion        numAppliances x 1 cell of 2 x 2 matrices
%                 summaryTable     MATLAB table, ready to paste into the report
%
%   ------------------------------------------------------------------
%   WHY SEVERAL DIFFERENT ACCURACY NUMBERS
%   ------------------------------------------------------------------
%   This is a MULTI-LABEL problem: several appliances can be on at once, so
%   a window is not simply right or wrong. Three views are reported because
%   each can mislead on its own.
%
%     accuracy    counts every appliance-window decision separately. With
%                 four appliances and 119 windows that is 476 decisions. It
%                 is the headline number, but it flatters a classifier that
%                 simply says OFF a lot, because most appliances are off in
%                 most windows.
%
%     macroF1     averages the F1 of each appliance equally. A classifier
%                 that never detects the quiet LED bank cannot hide behind
%                 its success on the loud kettle. This is the number that
%                 actually reflects whether disaggregation works.
%
%     exactMatch  the strictest view: the fraction of windows in which all
%                 four appliances were called correctly at once.
%
%   Reporting all three, and explaining the gap between them, is what the
%   rubric means by quantifying error rather than asserting success.
%
%   See also CONFUSIONMATRIX, CLASSIFYLOAD.

    % ---------------------------------------------------------------------
    % Accept the second output of classifyLoad, or a struct array
    % ---------------------------------------------------------------------
    predStates = coerceStates(predStates);
    trueStates = coerceStates(trueStates);

    if nargin < 3 || isempty(applianceNames)
        applianceNames = defaultNames(size(trueStates, 2));
    end

    if nargin < 4
        options = struct();
    end

    verbose = getParam(options, 'verbose', true);
    label = getParam(options, 'label', 'Evaluation');

    % ---------------------------------------------------------------------
    % Shape checks, with messages that say how to fix the problem
    % ---------------------------------------------------------------------
    if size(trueStates, 2) ~= size(predStates, 2)
        error('evaluateSystem:applianceMismatch', ...
            ['Ground truth has %d appliance columns but predictions have %d. ' ...
             'Both must use the same appliance order: %s.'], ...
            size(trueStates, 2), size(predStates, 2), strjoin(applianceNames, ', '));
    end

    if size(trueStates, 1) ~= size(predStates, 1)
        % A mismatch of one or two windows usually means the window count
        % was computed slightly differently in two places. Trim rather than
        % fail, but say so loudly.
        n = min(size(trueStates, 1), size(predStates, 1));

        warning('evaluateSystem:windowCountMismatch', ...
            ['Ground truth has %d windows but predictions have %d. ' ...
             'Comparing the first %d only - check that applyWindow and ' ...
             'makeWindowStates use the same windowLength and hopLength.'], ...
            size(trueStates, 1), size(predStates, 1), n);

        trueStates = trueStates(1:n, :);
        predStates = predStates(1:n, :);
    end

    [numWindows, numAppliances] = size(trueStates);

    % ---------------------------------------------------------------------
    % Per-appliance metrics
    % ---------------------------------------------------------------------
    confusion = cell(numAppliances, 1);

    perAppliance = repmat(struct('name', '', 'TP', 0, 'FP', 0, 'FN', 0, 'TN', 0, ...
        'accuracy', 0, 'precision', 0, 'recall', 0, 'specificity', 0, ...
        'f1', 0, 'support', 0), numAppliances, 1);

    for a = 1:numAppliances

        [cm, m] = confusionMatrix(trueStates(:, a), predStates(:, a));

        confusion{a} = cm;

        perAppliance(a).name = applianceNames{a};
        perAppliance(a).TP = m.TP;
        perAppliance(a).FP = m.FP;
        perAppliance(a).FN = m.FN;
        perAppliance(a).TN = m.TN;
        perAppliance(a).accuracy = m.accuracy;
        perAppliance(a).precision = m.precision;
        perAppliance(a).recall = m.recall;
        perAppliance(a).specificity = m.specificity;
        perAppliance(a).f1 = m.f1;
        perAppliance(a).support = m.support;

    end

    % ---------------------------------------------------------------------
    % Aggregate metrics
    % ---------------------------------------------------------------------
    totalDecisions = numWindows * numAppliances;
    correctDecisions = sum(sum(trueStates == predStates));

    overallAccuracy = correctDecisions / totalDecisions;

    macroF1 = mean([perAppliance.f1]);
    macroPrecision = mean([perAppliance.precision]);
    macroRecall = mean([perAppliance.recall]);

    % Micro-averaged F1: pool the counts first, then compute once.
    totalTP = sum([perAppliance.TP]);
    totalFP = sum([perAppliance.FP]);
    totalFN = sum([perAppliance.FN]);

    if (totalTP + totalFP) > 0
        microPrecision = totalTP / (totalTP + totalFP);
    else
        microPrecision = 0;
    end

    if (totalTP + totalFN) > 0
        microRecall = totalTP / (totalTP + totalFN);
    else
        microRecall = 0;
    end

    if (microPrecision + microRecall) > 0
        microF1 = 2 * microPrecision * microRecall / (microPrecision + microRecall);
    else
        microF1 = 0;
    end

    exactMatch = mean(all(trueStates == predStates, 2));
    hammingLoss = 1 - overallAccuracy;

    % ---------------------------------------------------------------------
    % Assemble the result
    % ---------------------------------------------------------------------
    results = struct();
    results.label = label;
    results.numWindows = numWindows;
    results.numAppliances = numAppliances;
    results.applianceNames = applianceNames;
    results.totalDecisions = totalDecisions;
    results.correctDecisions = correctDecisions;

    results.accuracy = overallAccuracy;
    results.macroF1 = macroF1;
    results.microF1 = microF1;
    results.macroPrecision = macroPrecision;
    results.macroRecall = macroRecall;
    results.exactMatch = exactMatch;
    results.hammingLoss = hammingLoss;

    results.perAppliance = perAppliance;
    results.confusion = confusion;

    results.summaryTable = table( ...
        applianceNames(:), ...
        [perAppliance.TP].', [perAppliance.FP].', ...
        [perAppliance.FN].', [perAppliance.TN].', ...
        [perAppliance.precision].', [perAppliance.recall].', ...
        [perAppliance.f1].', [perAppliance.support].', ...
        'VariableNames', {'Appliance', 'TP', 'FP', 'FN', 'TN', ...
                          'Precision', 'Recall', 'F1', 'WindowsON'});

    results.KPM = struct('accuracy', overallAccuracy, 'macroF1', macroF1);

    % ---------------------------------------------------------------------
    % Print
    % ---------------------------------------------------------------------
    if verbose
        printResults(results);
    end

end

% =========================================================================
% Printing
% =========================================================================
function printResults(r)

    line = repmat('=', 1, 74);

    fprintf('\n%s\n', line);
    fprintf('  %s\n', upper(r.label));
    fprintf('%s\n', line);

    fprintf('  Windows analysed        : %d\n', r.numWindows);
    fprintf('  Appliances              : %d (%s)\n', r.numAppliances, strjoin(r.applianceNames, ', '));
    fprintf('  Individual decisions    : %d\n', r.totalDecisions);
    fprintf('\n');

    fprintf('  KEY PERFORMANCE METRICS\n');
    fprintf('    Overall accuracy      : %6.2f %%\n', 100 * r.accuracy);
    fprintf('    Macro F1              : %6.4f\n', r.macroF1);
    fprintf('    Micro F1              : %6.4f\n', r.microF1);
    fprintf('    Exact-match windows   : %6.2f %%   (all appliances correct at once)\n', 100 * r.exactMatch);
    fprintf('    Hamming loss          : %6.4f   (fraction of decisions wrong)\n', r.hammingLoss);
    fprintf('\n');

    fprintf('  PER-APPLIANCE BREAKDOWN\n');
    fprintf('  %-16s %5s %5s %5s %5s %10s %8s %8s\n', ...
        'Appliance', 'TP', 'FP', 'FN', 'TN', 'Precision', 'Recall', 'F1');
    fprintf('  %s\n', repmat('-', 1, 70));

    for a = 1:numel(r.perAppliance)
        p = r.perAppliance(a);
        fprintf('  %-16s %5d %5d %5d %5d %10.3f %8.3f %8.3f\n', ...
            p.name, p.TP, p.FP, p.FN, p.TN, p.precision, p.recall, p.f1);
    end

    fprintf('\n');
    fprintf('  CONFUSION MATRICES  (rows: actual ON / OFF, cols: predicted ON / OFF)\n');

    for a = 1:numel(r.perAppliance)
        cm = r.confusion{a};
        fprintf('    %-16s [ %4d %4d ]\n', r.perAppliance(a).name, cm(1,1), cm(1,2));
        fprintf('    %-16s [ %4d %4d ]\n', '', cm(2,1), cm(2,2));
    end

    fprintf('%s\n\n', line);

end

% =========================================================================
% Accept either a logical matrix or the struct array from classifyLoad
% =========================================================================
function states = coerceStates(input)

    if islogical(input) || isnumeric(input)
        states = logical(input);
        return;
    end

    if isstruct(input)

        if isfield(input, 'states')
            numWindows = numel(input);
            states = false(numWindows, numel(input(1).states));
            for w = 1:numWindows
                states(w, :) = input(w).states;
            end
            return;
        end

        error('evaluateSystem:badStruct', ...
            ['A struct array was supplied but it has no "states" field. ' ...
             'Pass the second output of classifyLoad, which is a logical matrix.']);
    end

    error('evaluateSystem:badInput', ...
        'States must be a logical matrix or the struct array from classifyLoad.');

end

% =========================================================================
% Helpers
% =========================================================================
function names = defaultNames(n)

    names = cell(1, n);

    for k = 1:n
        names{k} = sprintf('Appliance%d', k);
    end

end

function value = getParam(params, name, defaultValue)

    if isfield(params, name) && ~isempty(params.(name))
        value = params.(name);
    else
        value = defaultValue;
    end

end
