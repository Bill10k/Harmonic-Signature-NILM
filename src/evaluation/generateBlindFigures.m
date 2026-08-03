function figureFiles = generateBlindFigures(output, params, tag)
%GENERATEBLINDFIGURES Figures for a blind or held-out recording.
%
%   figureFiles = GENERATEBLINDFIGURES(output, params, tag)
%
%   The main run produces figures from the simulation struct, which a blind
%   recording does not have - we only ever see the waveform. This function
%   draws what CAN be shown for an unseen recording, which is also what a
%   deployed meter would be able to display.
%
%   Four figures are written to figures/blind_<tag>:
%
%     blind1_waveform            the recording as measured, and after filtering
%     blind2_spectrum            spectrum of a representative window
%     blind3_coefficients        estimated appliance currents over time
%     blind4_timeline            predicted states, against truth if known
%
%   Figure 3 is the most informative of the four. It plots the raw output of
%   the decomposition - how much of each appliance the classifier believes is
%   present, before any thresholding - so the on/off decision can be seen
%   being made rather than merely reported.
%
%   INPUTS
%     output : struct from runPipeline, optionally containing .results
%     params : project parameter struct
%     tag    : short text used in the folder name, e.g. 'seed7'
%
%   OUTPUT
%     figureFiles : cell array of the files written

    if nargin < 3 || isempty(tag)
        tag = 'run';
    end

    outDir = fullfile('figures', ['blind_' tag]);

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    figureFiles = {};

    fs = params.fs;
    signal = output.inputSignal;
    filtered = output.filteredSignal;
    t = (0:numel(signal)-1).' / fs;

    names = output.classifyInfo.applianceNames;
    numAppliances = numel(names);
    centreTimes = output.featureInfo.centerTime_s;
    predStates = output.predStates;

    hasTruth = isfield(output, 'results');

    % =====================================================================
    % Figure 1: the measured waveform
    % =====================================================================
    fig = figure('Visible', 'off', 'Name', 'Blind recording', ...
        'Position', [100 100 1150 700]);

    subplot(2, 1, 1);
    plot(t, signal, 'LineWidth', 0.7);
    grid on;
    xlabel('Time (s)'); ylabel('Current (A)');
    title('Aggregate current as measured (unseen recording)');
    xlim([0 max(t)]);

    subplot(2, 1, 2);
    plot(t, filtered, 'LineWidth', 0.7);
    grid on;
    xlabel('Time (s)'); ylabel('Current (A)');
    title('After FIR low-pass filtering');
    xlim([0 max(t)]);

    figureFiles{end+1} = saveFig(fig, outDir, 'blind1_waveform');

    % =====================================================================
    % Figure 2: spectrum of the busiest window
    % =====================================================================
    rmsSeries = [output.featureSet.RMS];
    [~, busiest] = max(rmsSeries);

    s1 = output.frameInfo.startSamples(busiest);
    s2 = output.frameInfo.stopSamples(busiest);
    winCoeffs = output.frameInfo.winCoeffs;

    segment = filtered(s1:s2) .* winCoeffs;

    [freq, mag] = computeFFT(segment, fs, winCoeffs);

    fig = figure('Visible', 'off', 'Name', 'Blind spectrum', ...
        'Position', [110 110 1100 520]);

    plot(freq, mag, 'LineWidth', 1.1);
    grid on; hold on;

    % Mark the analysed harmonics so the reader can see what is being read.
    orders = output.featureInfo.analysisHarmonics;
    harmonicFreqs = orders * params.f0;

    for k = 1:numel(harmonicFreqs)
        plot([harmonicFreqs(k) harmonicFreqs(k)], [0 max(mag)*1.05], ':', ...
            'Color', [0.6 0.6 0.6], 'LineWidth', 0.7);
    end

    xlabel('Frequency (Hz)'); ylabel('Magnitude (A peak)');
    title(sprintf('Harmonic spectrum of the highest-current window (t = %.2f s)', ...
        centreTimes(busiest)));
    xlim([0 max(harmonicFreqs) * 1.25]);

    figureFiles{end+1} = saveFig(fig, outDir, 'blind2_spectrum');

    % =====================================================================
    % Figure 3: estimated appliance currents, the decomposition itself
    % =====================================================================
    if isfield(output.classifyInfo, 'coefficients') && ...
            ~isempty(output.classifyInfo.coefficients)

        coefficients = output.classifyInfo.coefficients;
        threshold = output.classifyInfo.onThreshold;

        fig = figure('Visible', 'off', 'Name', 'Estimated appliance currents', ...
            'Position', [120 120 1150 750]);

        for a = 1:numAppliances

            subplot(numAppliances, 1, a);
            plot(centreTimes, coefficients(:, a), 'LineWidth', 1.3);
            grid on; hold on;

            plot([0 max(centreTimes)], [threshold threshold], '--', 'LineWidth', 1.0);

            ylabel('x rated');
            title(sprintf('%s   -   estimated current as a fraction of its rating', names{a}), ...
                'Interpreter', 'none');
            xlim([0 max(centreTimes)]);
            ylim([0 max(1.6, max(coefficients(:, a)) * 1.1)]);

            if a == 1
                legend({'Estimated', 'ON threshold'}, 'Location', 'northeast');
            end

            if a == numAppliances
                xlabel('Window centre time (s)');
            end

        end

        figureFiles{end+1} = saveFig(fig, outDir, 'blind3_coefficients');
    end

    % =====================================================================
    % Figure 4: predicted timeline, with truth overlaid when we have it
    % =====================================================================
    fig = figure('Visible', 'off', 'Name', 'Predicted appliance timeline', ...
        'Position', [130 130 1150 750]);

    for a = 1:numAppliances

        subplot(numAppliances, 1, a);
        hold on;

        stairs(centreTimes, double(predStates(:, a)), 'LineWidth', 1.5);

        grid on;
        ylim([-0.2 1.3]);
        xlim([0 max(centreTimes)]);
        ylabel('State');

        if hasTruth
            title(sprintf('%s   -   F1 = %.3f', names{a}, ...
                output.results.perAppliance(a).f1), 'Interpreter', 'none');
        else
            title(sprintf('%s   -   predicted ON for %.1f%% of the recording', ...
                names{a}, 100*mean(predStates(:, a))), 'Interpreter', 'none');
        end

        if a == numAppliances
            xlabel('Window centre time (s)');
        end

    end

    figureFiles{end+1} = saveFig(fig, outDir, 'blind4_timeline');

    fprintf('  Figures              : %s\n', outDir);

end

% =========================================================================
function filename = saveFig(fig, outDir, name)

    filename = fullfile(outDir, [name '.png']);
    saveas(fig, filename);
    close(fig);

end
