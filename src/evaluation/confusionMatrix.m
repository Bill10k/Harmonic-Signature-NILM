function [cm, metrics] = confusionMatrix(trueLabels, predLabels)
%CONFUSIONMATRIX Binary confusion matrix and derived metrics for one appliance.
%
%   [cm, metrics] = CONFUSIONMATRIX(trueLabels, predLabels)
%
%   INPUTS
%     trueLabels : logical vector, true ON/OFF state per window
%     predLabels : logical vector, predicted ON/OFF state per window
%
%   OUTPUTS
%     cm      : 2 x 2 matrix laid out as
%
%                              predicted ON   predicted OFF
%                 actual ON  [     TP              FN      ]
%                 actual OFF [     FP              TN      ]
%
%     metrics : struct with TP, FP, FN, TN, accuracy, precision, recall,
%               specificity, f1 and support
%
%   DEFINITIONS, IN THE LANGUAGE OF THIS PROJECT
%     TP  the appliance was on and we said it was on
%     FN  the appliance was on and we missed it
%     FP  the appliance was off and we wrongly reported it
%     TN  the appliance was off and we correctly stayed silent
%
%     precision = TP / (TP + FP)
%         Of the windows where we claimed this appliance was running, how
%         many really were. Low precision means we invent appliances.
%
%     recall = TP / (TP + FN)
%         Of the windows where it really was running, how many we caught.
%         Low recall means we miss appliances that are there.
%
%     f1 = harmonic mean of precision and recall
%         The single number the brief asks us to report, because it refuses
%         to be fooled by a classifier that is good at only one of the two.
%
%   EDGE CASES
%     Precision is undefined when nothing was predicted ON, and recall is
%     undefined when the appliance was never actually ON. Rather than return
%     NaN and poison the macro average, both are defined as 1 when the
%     denominator is zero AND no error was made, and 0 otherwise. This is the
%     usual convention and it is stated in the report.
%
%   See also EVALUATESYSTEM.

    trueLabels = logical(trueLabels(:));
    predLabels = logical(predLabels(:));

    if numel(trueLabels) ~= numel(predLabels)
        error('confusionMatrix:lengthMismatch', ...
            'trueLabels has %d entries but predLabels has %d.', ...
            numel(trueLabels), numel(predLabels));
    end

    TP = sum(trueLabels & predLabels);
    FN = sum(trueLabels & ~predLabels);
    FP = sum(~trueLabels & predLabels);
    TN = sum(~trueLabels & ~predLabels);

    cm = [TP, FN; FP, TN];

    total = TP + FN + FP + TN;

    metrics = struct();
    metrics.TP = TP;
    metrics.FN = FN;
    metrics.FP = FP;
    metrics.TN = TN;
    metrics.total = total;
    metrics.support = TP + FN;                  % windows where it really was on

    if total > 0
        metrics.accuracy = (TP + TN) / total;
    else
        metrics.accuracy = 0;
    end

    metrics.precision = safeRatio(TP, TP + FP, FP == 0 && FN == 0);
    metrics.recall = safeRatio(TP, TP + FN, FP == 0 && FN == 0);
    metrics.specificity = safeRatio(TN, TN + FP, FP == 0 && FN == 0);

    if (metrics.precision + metrics.recall) > 0
        metrics.f1 = 2 * (metrics.precision * metrics.recall) / ...
                         (metrics.precision + metrics.recall);
    else
        metrics.f1 = 0;
    end

    metrics.layout = 'rows: actual ON, actual OFF. columns: predicted ON, predicted OFF';

end

% =========================================================================
% Helper: ratio that does not divide by zero
% If the denominator is zero the result depends on whether the classifier
% was actually perfect on this appliance (no errors at all) or simply never
% had the chance to be right.
% =========================================================================
function value = safeRatio(numerator, denominator, perfectWhenEmpty)

    if denominator > 0
        value = numerator / denominator;
    elseif perfectWhenEmpty
        value = 1;
    else
        value = 0;
    end

end
