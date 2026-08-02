function params = defaultParameters()

params.fs = 4000;
params.f0 = 50;
params.duration = 12;

params.windowLength = 0.20;
params.hopLength = 0.10;

params.maxHarmonic = 15;

params.analysisHarmonics = [1 3 5 7 9 11 13 15];

params.plotResults = true;
params.saveFigures = true;

end