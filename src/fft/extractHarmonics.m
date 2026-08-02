function harmonics = extractHarmonics(frequency, magnitude)

fundamental = 50;

numHarmonics = 10;

harmonics = zeros(numHarmonics,2);

for k = 1:numHarmonics

    targetFreq = k*fundamental;

    [~,index] = min(abs(frequency-targetFreq));

    harmonics(k,1) = targetFreq;

    harmonics(k,2) = magnitude(index);

end

disp('Frequency      Magnitude')

disp(harmonics)

end