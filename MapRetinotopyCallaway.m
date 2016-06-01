function [] = MapRetinotopyCallaway(AnimalName,Date,Chans)
% MapRetinotopyCallaway.m
%
%  Will take data from a retinotopic mapping experiment and extract the
%   retinotopy of the LFP recording electrode. The stimulus used here is
%   the periodic drifting bar with flashing counter-phase checkerboard from
%   the file RetinotopyCallaway.m
%
%INPUT: AnimalName - unique identifier for the animal as a number, e.g.
%            12345
%       Date - date of the experiment, e.g. 20160525
%       Chans - channel numbers, input as [6,8], defaults to 6 and 8
%OUTPUT:
%
% Created: 2016/05/31, 24 Cummington, Boston
%  Byron Price
% Updated: 2016/05/31
%  By: Byron Price

EphysFileName = strcat('RetinoData',num2str(Date),'_',num2str(AnimalName));

readall(EphysFileName);

StimulusFileName = strcat('RetinoStim',num2str(Date),'_',num2str(AnimalName),'.mat');
EphysFileName = strcat(EphysFileName,'.mat');
load(EphysFileName)
load(StimulusFileName)

if nargin < 3
    Chans = [6,8];
end

sampleFreq = adfreq;

% tsevs are the strobed times of stimulus onset, then offset
%  Onset at tsevs{1,33}(2), offset at tsevs{1,33}(3), onset at
%  tsevs{1,33}(4), offset at 5, etc.
% allad contains the continuous data from each channel, which appear to be
%  recorded at 1000 Hz rather than 40,000

totalAD = size(allad,2);
totalSEVS = size(tsevs,2);

for ii=1:totalAD
    if isempty(allad{1,ii})
        continue;
    else
        break;
    end
end
channelStart = ii;

for ii=1:totalSEVS
    if isempty(allad{1,ii})
        continue;
    else
        break;
    end
end
strobeStart = ii;

dataLength = length(allad{1,channelStart+Chans(1)-1});
numChans = length(Chans);
ChanData = zeros(dataLength,numChans);
for ii=1:numChans
    ChanData(:,ii) = allad{1,channelStart+Chans(ii)-1};
end
timeStamps = 0:1/sampleFreq:dataLength/sampleFreq-1/sampleFreq;

if length(timeStamps) ~= dataLength
    display('Error: Review allad cell array and timing')
    return;
end
strobeData = tsevs{1,strobeStart};
totalStrobes = length(strobeData);

timeWindow = 0.05; % 50 ms sliding window
Response = zeros(dataPoints/reps,numChans);
timeFrames = round(timeWindow*sampleFreq);


for ii=1:numChans
    count = 1;
    for jj=1:dataPoints/reps
        temp = 0;
        for kk=1:reps
            stimOnset = strobeData(jj+dataPoints/reps*(kk-1));
            [~,index] = min(abs(timeStamps-stimOnset));
            temp = temp+ChanData(index+delay:index+timeFrames,ii);
        end
        avg = temp./reps;
        Response(count,ii) = max(avg)-min(avg);
        count = count+1;
    end
end
cutOff = prctile(Response,98);

Indeces = cell(1,numChans);
figure();hold on;
for ii=1:numChans
        Indeces{ii} = find(Response(:,ii)>cutOff(ii));
        subplot(2,1,ii);plot(stimulusLocs(Indeces{ii},1),stimulusLocs(Indeces{ii},2),'*b','LineWidth',2);
end
hold off;

end
