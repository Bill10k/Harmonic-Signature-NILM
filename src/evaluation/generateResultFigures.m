function figureFiles = generateResultFigures(sim, disturbedSignal, output, results, params)
%GENERATERESULTFIGURES Produces the figures used in the report and slides.
%
%   figureFiles = GENERATERESULTFIGURES(sim, disturbedSignal, output, results, params)
%
%   Six figures are written to params.figureDir:
%
%     result1_clean_vs_disturbed     what the disturbances did to the signal
%     result2_filter_response        the FIR filter we designed
%     result3_spectrum_before_after  evidence the filtering works
%     result4_feature_timeline       RMS and THD across the recording
%     result5_confusion              predicted against true appliance states
%     result6_performance            per-appliance precision, recall and F1
%
%   Figure 3 is the one the brief specifically demands: before-and-after
%   spectra showing that our filtering suppresses the supply disturbance.
%
%   INPUTS
%     sim             : struct from model_four_appliances
%     disturbedSignal : the aggregate current after disturbances
%     output          : struct from runPipeline
%     results         : struct from evaluateSystem
%     params          : project parameter struct
%
%   OUTPUT
%     figureFiles : cell array of the files written

    outDir = getParam(params, 'figureDir', fullfile('figures', 'results'));

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    saveFigs = getParam(params, 'saveFigures', true);

    figureFiles = {};

    t = sim.t;
    fs = params.fs;
    names = output.classifyInfo.applianceNames;
    numAppliances = numel(names);

    % =====================================================================
    % Figure 1: clean against disturbed aggregate current
    % =====================================================================
    fig = figure('Visible', 'off', 'Name', 'Clean vs disturbed', ...
        'Position', [100 100 1150 750]);

    subplot(3, 1, 1);
    plot(t, sim.aggregateClean, 'LineWidth', 0.8);
    grid on;
    xlabel('Time (s)'); ylabel('Current (A)');
    title('Clean aggregate current');
    xlim([0 max(t)]);

    subplot(3, 1, 2);
    plot(t, disturbedSignal, 'LineWidth', 0.8);
    grid on;
    xlabel('Time (s)'); ylabel('Current (A)');
    title('After sag, background harmonics, interruption and noise');
    xlim([0 max(t)]);

    subplot(3, 1, 3);
    plot(t, disturbedSignal - sim.aggregateClean, 'LineWidth', 0.8);
    grid on;
    xlabel('Time (s)'); ylabel('Difference (A)');
    title('What the disturbances added or removed');
    xlim([0 max(t)]);

    figureFiles{end+1} = saveFigure(fig, outDir, 'result1_clean_vs_disturbed', saveFigs);

    % =====================================================================
    % Figure 2: FIR filter magnitude response
    %
    % Computed from the actual coefficients used, so the figure can never
    % disagree with the filter that ran.
    % =====================================================================
    coeffs = output.filterInfo.coeffs;

    nfft = 4096;
    H = fft(coeffs, nfft);
    freqAxis = (0:nfft-1) * (fs / nfft);
    half = 1:floor(nfft/2);

    magDb = 20 * log10(abs(H(half)) + eps);

    fig = figure('Visible', 'off', 'Name', 'FIR filter response', ...
        'Position', [110 110 1100 700]);

    subplot(2, 1, 1);
    plot(freqAxis(half), magDb, 'LineWidth', 1.2);
    grid on; hold on;

    cutoff = output.filterInfo.cutoffHz;
    plot([cutoff cutoff], [-120 5], '--', 'LineWidth', 1.0);
    plot([750 750], [-120 5], ':', 'LineWidth', 1.0);

    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
    title(sprintf('FIR low-pass response: order %d, %s window, cutoff %.0f Hz', ...
        output.filterInfo.order, output.filterInfo.windowType, cutoff));
    legend({'Filter response', 'Cutoff', '15th harmonic (750 Hz)'}, 'Location', 'southwest');
    xlim([0 fs/2]); ylim([-120 5]);

    subplot(2, 1, 2);
    plot(freqAxis(half), magDb, 'LineWidth', 1.2);
    grid on; hold on;
    plot([750 750], [-6 1], ':', 'LineWidth', 1.0);
    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
    title('Passband detail: every analysed harmonic must pass unattenuated');
    xlim([0 1000]); ylim([-6 1]);

    figureFiles{end+1} = saveFigure(fig, outDir, 'result2_filter_response', saveFigs);

    % =====================================================================
    % Figure 3: spectrum before and after filtering
    %
    % This is the evidence the brief asks for. A window is chosen that sits
    % inside the voltage sag, because that is where the disturbance is
    % strongest and the filtering has the most to do.
    % =====================================================================
    sagCentre = getParam(params, 'sagStartTime', 4.0) + getParam(params, 'sagDuration', 0.3)/2;

    [~, wSag] = min(abs(output.featureInfo.centerTime_s - sagCentre));

    s1 = output.frameInfo.startSamples(wSag);
    s2 = output.frameInfo.stopSamples(wSag);
    winCoeffs = output.frameInfo.winCoeffs;

    rawSegment = disturbedSignal(s1:s2) .* winCoeffs;
    filtSegment = output.filteredSignal(s1:s2) .* winCoeffs;

    [fRaw, mRaw] = computeFFT(rawSegment, fs, winCoeffs);
    [fFilt, mFilt] = computeFFT(filtSegment, fs, winCoeffs);

    % Plotted in DECIBELS, not amperes. On a linear axis the fundamental is
    % roughly 8 A while the out-of-band noise the filter removes is a few
    % milliamps, so the entire effect of the filter is invisible - the two
    % plots look identical. A logarithmic axis shows four orders of
    % magnitude at once, which is what makes the attenuation legible.
    refLevel = max(mRaw);

    dbRaw = 20 * log10(mRaw / refLevel + eps);
    dbFilt = 20 * log10(mFilt / refLevel + eps);

    fig = figure('Visible', 'off', 'Name', 'Spectrum before and after filtering', ...
        'Position', [120 120 1150 750]);

    subplot(2, 1, 1);
    plot(fRaw, dbRaw, 'LineWidth', 1.0);
    grid on; hold on;
    plot(fFilt, dbFilt, 'LineWidth', 1.0);

    yl = [-140 5];
    plot([cutoff cutoff], yl, 'k--', 'LineWidth', 1.0);

    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB, relative to fundamental)');
    title(sprintf('Spectrum before and after FIR filtering, window at t = %.2f s (inside the sag)', ...
        output.featureInfo.centerTime_s(wSag)));
    legend({'Before filtering', 'After filtering', 'Cutoff 775 Hz'}, 'Location', 'northeast');
    xlim([0 fs/2]); ylim(yl);

    % Quantify the suppression actually achieved above the cutoff, so the
    % report can state a number rather than point at a picture.
    stopBand = fRaw > cutoff;

    if any(stopBand)
        beforeStop = 20*log10(sqrt(mean(mRaw(stopBand).^2)) / refLevel + eps);
        afterStop = 20*log10(sqrt(mean(mFilt(stopBand).^2)) / refLevel + eps);
        suppression = beforeStop - afterStop;
    else
        suppression = 0;
    end

    subplot(2, 1, 2);
    plot(fRaw, dbRaw, 'LineWidth', 1.0);
    grid on; hold on;
    plot(fFilt, dbFilt, 'LineWidth', 1.0);
    plot([cutoff cutoff], [-100 5], 'k--', 'LineWidth', 1.0);

    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
    title(sprintf('Detail to 1200 Hz: out-of-band content suppressed by %.1f dB', suppression));
    legend({'Before filtering', 'After filtering', 'Cutoff'}, 'Location', 'northeast');
    xlim([0 1200]); ylim([-100 5]);

    fprintf('  Out-of-band suppression above %.0f Hz: %.1f dB\n', cutoff, suppression);

    figureFiles{end+1} = saveFigure(fig, outDir, 'result3_spectrum_before_after', saveFigs);

    % =====================================================================
    % Figure 4: feature timeline
    % =====================================================================
    centreTimes = output.featureInfo.centerTime_s;
    rmsSeries = [output.featureSet.RMS];
    thdSeries = [output.featureSet.THD];
    liveSeries = [output.featureSet.isLive];

    fig = figure('Visible', 'off', 'Name', 'Feature timeline', ...
        'Position', [130 130 1150 750]);

    subplot(3, 1, 1);
    plot(centreTimes, rmsSeries, 'LineWidth', 1.3);
    grid on;
    xlabel('Window centre time (s)'); ylabel('RMS current (A)');
    title('RMS current per analysis window');
    xlim([0 max(centreTimes)]);

    subplot(3, 1, 2);
    plot(centreTimes, thdSeries, 'LineWidth', 1.3);
    grid on;
    xlabel('Window centre time (s)'); ylabel('THD (%)');
    title('Total harmonic distortion per window');
    xlim([0 max(centreTimes)]);

    subplot(3, 1, 3);
    stairs(centreTimes, double(liveSeries), 'LineWidth', 1.4);
    grid on;
    xlabel('Window centre time (s)'); ylabel('Supply live');
    title('Windows where the fundamental collapsed (supply interruption)');
    ylim([-0.2 1.2]);
    xlim([0 max(centreTimes)]);

    figureFiles{end+1} = saveFigure(fig, outDir, 'result4_feature_timeline', saveFigs);

    % =====================================================================
    % Figure 5: predicted against true state, per appliance
    % =====================================================================
    trueStates = sim.windowStates;
    predStates = output.predStates;

    numCompare = min(size(trueStates, 1), size(predStates, 1));
    trueStates = trueStates(1:numCompare, :);
    predStates = predStates(1:numCompare, :);
    tPlot = centreTimes(1:numCompare);

    fig = figure('Visible', 'off', 'Name', 'Predicted vs true states', ...
        'Position', [140 140 1150 800]);

    for a = 1:numAppliances

        subplot(numAppliances, 1, a);
        hold on;

        stairs(tPlot, double(trueStates(:, a)) * 1.0, 'LineWidth', 1.6);
        stairs(tPlot, double(predStates(:, a)) * 0.9, '--', 'LineWidth', 1.4);

        wrong = trueStates(:, a) ~= predStates(:, a);

        if any(wrong)
            plot(tPlot(wrong), 0.5*ones(sum(wrong), 1), 'x', 'LineWidth', 1.2);
        end

        grid on;
        ylim([-0.2 1.3]);
        xlim([0 max(tPlot)]);
        ylabel('State');
        title(sprintf('%s   -   F1 = %.3f', names{a}, results.perAppliance(a).f1));

        if a == 1
            legend({'True', 'Predicted', 'Errors'}, 'Location', 'northeast');
        end

        if a == numAppliances
            xlabel('Window centre time (s)');
        end

    end

    figureFiles{end+1} = saveFigure(fig, outDir, 'result5_confusion', saveFigs);

    % =====================================================================
    % Figure 6: per-appliance performance bars
    % =====================================================================
    precision = [results.perAppliance.precision];
    recall = [results.perAppliance.recall];
    f1 = [results.perAppliance.f1];

    fig = figure('Visible', 'off', 'Name', 'Performance by appliance', ...
        'Position', [150 150 1100 600]);

    bar([precision(:), recall(:), f1(:)], 'grouped');
    grid on;
    set(gca, 'XTickLabel', names);
    ylabel('Score');
    ylim([0 1.05]);
    title(sprintf('Performance by appliance   -   overall accuracy %.1f%%, macro-F1 %.3f', ...
        100*results.accuracy, results.macroF1));
    legend({'Precision', 'Recall', 'F1'}, 'Location', 'southeast');

    figureFiles{end+1} = saveFigure(fig, outDir, 'result6_performance', saveFigs);

end

% =========================================================================
% Helpers
% =========================================================================
function filename = saveFigure(fig, outDir, name, doSave)

    filename = fullfile(outDir, [name '.png']);

    if doSave
        saveas(fig, filename);
    end

    close(fig);

end

function value = getParam(params, name, defaultValue)

    if isfield(params, name) && ~isempty(params.(name))
        value = params.(name);
    else
        value = defaultValue;
    end

end
