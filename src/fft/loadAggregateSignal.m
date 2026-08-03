function [signal, fs, loadInfo] = loadAggregateSignal(source, params)
%LOADAGGREGATESIGNAL Reads an aggregate current waveform from a file.
%
%   [signal, fs, loadInfo] = LOADAGGREGATESIGNAL(source)
%   [signal, fs, loadInfo] = LOADAGGREGATESIGNAL(source, params)
%
%   This is the door through which the blind benchmark waveform enters the
%   system. Until it existed, the only way a signal could reach the pipeline
%   was generateTestSignal.m, which builds a fixed synthetic sine wave in
%   code - so the project could not be run on any data it had not made
%   itself.
%
%   Nothing downstream needs to change to analyse a new recording: load it
%   here, and the rest of the pipeline is identical.
%
%   ACCEPTED SOURCES
%     .mat  a MATLAB file. The waveform is found by looking for, in order:
%           a variable named one of aggregateCurrent, aggregate, current,
%           signal, i, data, x; otherwise the only numeric vector present.
%           A sampling rate is taken from fs, Fs, samplingRate or sampleRate
%           if any of those exist.
%     .csv  a comma-separated file. If it has one column that column is the
%           waveform. If it has two, the first is assumed to be time and the
%           sampling rate is derived from it. A single header line is skipped
%           automatically.
%     .txt  whitespace or comma separated, same rules as .csv.
%     .wav  read with audioread, sampling rate taken from the file.
%     numeric vector  passed straight through, for testing.
%
%   INPUTS
%     source : path to the file, or a numeric vector
%     params : optional project parameter struct. params.fs is used only as
%              a fallback when the file itself does not state a rate.
%
%   OUTPUTS
%     signal   : column vector of current samples
%     fs       : sampling frequency actually used, Hz
%     loadInfo : struct describing where the data and the rate came from
%
%   The function is deliberately noisy about assumptions. If it has to guess
%   the sampling rate it says so, because analysing a recording at the wrong
%   rate silently shifts every harmonic and would invalidate the results
%   without producing any error.

    if nargin < 2
        params = struct();
    end

    fallbackFs = getParam(params, 'fs', 4000);

    loadInfo = struct();
    loadInfo.source = '';
    loadInfo.variableUsed = '';
    loadInfo.fsSource = '';
    loadInfo.assumedFs = false;

    % ---------------------------------------------------------------------
    % A vector was passed directly
    % ---------------------------------------------------------------------
    if isnumeric(source)
        signal = source(:);
        fs = fallbackFs;
        loadInfo.source = 'numeric vector supplied directly';
        loadInfo.fsSource = 'params.fs';
        loadInfo.assumedFs = true;
        loadInfo.numSamples = numel(signal);
        loadInfo.duration_s = numel(signal) / fs;
        warnAboutAssumedRate(fs);
        return;
    end

    if ~ischar(source) && ~isstring(source)
        error('loadAggregateSignal:badSource', ...
            'source must be a file path or a numeric vector.');
    end

    source = char(source);

    if exist(source, 'file') ~= 2
        error('loadAggregateSignal:fileNotFound', ...
            ['Cannot find "%s".\n' ...
             'Check the path, and remember MATLAB looks relative to the ' ...
             'current folder unless you give an absolute path.'], source);
    end

    loadInfo.source = source;

    [~, ~, ext] = fileparts(source);

    fs = [];

    switch lower(ext)

        case '.mat'
            [signal, fs, loadInfo] = readMatFile(source, loadInfo);

        case {'.csv', '.txt', '.dat'}
            [signal, fs, loadInfo] = readTextFile(source, loadInfo);

        case '.wav'
            [signal, fs] = audioread(source);
            signal = signal(:, 1);
            loadInfo.variableUsed = 'audio channel 1';
            loadInfo.fsSource = 'wav file header';

        otherwise
            error('loadAggregateSignal:unsupportedFormat', ...
                ['Unsupported file type "%s". Supported: .mat, .csv, .txt, .dat, .wav.\n' ...
                 'If the blind data arrives in another format, convert it or ' ...
                 'add a case to loadAggregateSignal.m.'], ext);
    end

    % ---------------------------------------------------------------------
    % Fall back on the project sampling rate if the file did not state one
    % ---------------------------------------------------------------------
    if isempty(fs) || ~isfinite(fs) || fs <= 0
        fs = fallbackFs;
        loadInfo.fsSource = 'params.fs (file did not state a rate)';
        loadInfo.assumedFs = true;
        warnAboutAssumedRate(fs);
    end

    signal = signal(:);

    % ---------------------------------------------------------------------
    % Sanity checks that catch a mis-read file before it wastes an analysis
    % ---------------------------------------------------------------------
    if isempty(signal)
        error('loadAggregateSignal:emptySignal', 'No samples were read from "%s".', source);
    end

    if any(~isfinite(signal))
        numBad = sum(~isfinite(signal));
        warning('loadAggregateSignal:nonFiniteSamples', ...
            'Replaced %d non-finite sample(s) with zero.', numBad);
        signal(~isfinite(signal)) = 0;
    end

    loadInfo.numSamples = numel(signal);
    loadInfo.duration_s = numel(signal) / fs;
    loadInfo.fs = fs;
    loadInfo.rms_A = sqrt(mean(signal.^2));
    loadInfo.peak_A = max(abs(signal));

    % A DC offset in a current waveform is almost always a measurement
    % artefact rather than a real load, and it distorts the harmonic
    % analysis, so flag it rather than silently analysing it.
    dcOffset = mean(signal);

    if abs(dcOffset) > 0.05 * loadInfo.rms_A
        warning('loadAggregateSignal:dcOffset', ...
            ['The waveform has a DC offset of %.4f A (%.1f%% of its RMS). ' ...
             'That is unusual for a current measurement and may indicate a ' ...
             'scaling or format problem.'], dcOffset, 100*abs(dcOffset)/loadInfo.rms_A);
    end

    loadInfo.dcOffset_A = dcOffset;

end

% =========================================================================
% .mat files
% =========================================================================
function [signal, fs, loadInfo] = readMatFile(source, loadInfo)

    contents = load(source);
    names = fieldnames(contents);

    % Preferred names for the waveform, in order.
    preferred = {'aggregateCurrent', 'aggregate', 'aggregateClean', ...
                 'current', 'signal', 'blindSignal', 'i', 'data', 'x'};

    signal = [];

    for k = 1:numel(preferred)
        if isfield(contents, preferred{k}) && isnumeric(contents.(preferred{k}))
            candidate = contents.(preferred{k});
            if isvector(candidate) && numel(candidate) > 1
                signal = candidate(:);
                loadInfo.variableUsed = preferred{k};
                break;
            end
        end
    end

    % Nothing recognised: accept the only numeric vector in the file.
    if isempty(signal)

        vectorNames = {};

        for k = 1:numel(names)
            value = contents.(names{k});
            if isnumeric(value) && isvector(value) && numel(value) > 1
                vectorNames{end+1} = names{k}; %#ok<AGROW>
            end
        end

        if numel(vectorNames) == 1
            signal = contents.(vectorNames{1});
            signal = signal(:);
            loadInfo.variableUsed = vectorNames{1};
        elseif numel(vectorNames) > 1
            error('loadAggregateSignal:ambiguousVariable', ...
                ['"%s" contains several numeric vectors (%s) and none has a ' ...
                 'recognised name. Rename the waveform to aggregateCurrent, ' ...
                 'or load it yourself and pass the vector in directly.'], ...
                source, strjoin(vectorNames, ', '));
        else
            error('loadAggregateSignal:noVector', ...
                'No numeric vector was found in "%s". Variables present: %s.', ...
                source, strjoin(names, ', '));
        end
    end

    % Sampling rate, if the file carries one.
    fs = [];
    rateNames = {'fs', 'Fs', 'samplingRate', 'sampleRate', 'SamplingFrequency'};

    for k = 1:numel(rateNames)
        if isfield(contents, rateNames{k}) && isscalar(contents.(rateNames{k}))
            fs = double(contents.(rateNames{k}));
            loadInfo.fsSource = sprintf('variable "%s" in the .mat file', rateNames{k});
            break;
        end
    end

    % Some files store a time vector instead of a rate.
    if isempty(fs) && isfield(contents, 't') && isnumeric(contents.t) && numel(contents.t) > 1
        dt = mean(diff(contents.t(:)));
        if dt > 0
            fs = 1 / dt;
            loadInfo.fsSource = 'derived from the time vector "t"';
        end
    end

end

% =========================================================================
% Text and CSV files
% =========================================================================
function [signal, fs, loadInfo] = readTextFile(source, loadInfo)

    raw = [];
    fs = [];

    % Try a straight numeric read first; if the file has a header line this
    % throws, and we retry while skipping one row.
    try
        raw = readNumericMatrix(source, 0);
    catch
        raw = readNumericMatrix(source, 1);
        loadInfo.headerSkipped = true;
    end

    if isempty(raw)
        error('loadAggregateSignal:emptyFile', 'No numeric data was read from "%s".', source);
    end

    if size(raw, 2) == 1
        signal = raw(:, 1);
        loadInfo.variableUsed = 'single column';

    elseif size(raw, 2) >= 2
        % Two or more columns: assume column 1 is time if it increases
        % monotonically by a constant step.
        firstCol = raw(:, 1);
        steps = diff(firstCol);

        looksLikeTime = all(steps > 0) && (std(steps) < 1e-6 * mean(steps) + eps);

        if looksLikeTime
            dt = mean(steps);
            fs = 1 / dt;
            signal = raw(:, 2);
            loadInfo.variableUsed = 'column 2 (column 1 read as time)';
            loadInfo.fsSource = 'derived from the time column';
        else
            signal = raw(:, 1);
            loadInfo.variableUsed = 'column 1';
        end
    end

end

% =========================================================================
% Numeric read that works with commas or whitespace, without toolboxes
% =========================================================================
function matrix = readNumericMatrix(source, skipRows)

    fid = fopen(source, 'r');

    if fid < 0
        error('loadAggregateSignal:cannotOpen', 'Could not open "%s".', source);
    end

    cleanupObj = onCleanup(@() fclose(fid));

    for k = 1:skipRows
        fgetl(fid);
    end

    rows = {};

    while true

        line = fgetl(fid);

        if ~ischar(line)
            break;
        end

        line = strtrim(line);

        if isempty(line) || line(1) == '#' || line(1) == '%'
            continue;
        end

        values = sscanf(strrep(line, ',', ' '), '%f').';

        if ~isempty(values)
            rows{end+1} = values; %#ok<AGROW>
        end

    end

    if isempty(rows)
        matrix = [];
        return;
    end

    widths = cellfun(@numel, rows);

    if any(widths ~= widths(1))
        error('loadAggregateSignal:raggedFile', ...
            'The file has rows of differing widths (%d to %d columns).', min(widths), max(widths));
    end

    matrix = vertcat(rows{:});

end

% =========================================================================
% Helpers
% =========================================================================
function warnAboutAssumedRate(fs)

    warning('loadAggregateSignal:assumedSamplingRate', ...
        ['The file did not state a sampling rate, so %g Hz was assumed.\n' ...
         'If the blind recording was sampled at a different rate, every ' ...
         'harmonic will be read at the wrong frequency and the results will ' ...
         'be wrong without any error being raised. Confirm the rate before ' ...
         'trusting the output.'], fs);

end

function value = getParam(params, name, defaultValue)

    if isfield(params, name) && ~isempty(params.(name))
        value = params.(name);
    else
        value = defaultValue;
    end

end
