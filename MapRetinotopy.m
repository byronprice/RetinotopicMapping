function [] = MapRetinotopy(AnimalName,Date,Chans)
% MapRetinotopy.m
%
%  Will take data from a retinotopic mapping experiment and extract the 
%   retinotopy of the LFP recording electrode.
%INPUT: AnimalName - unique identifier for the animal as a number, e.g.
%            12345
%       Date - date of the experiment, e.g. 20160525
%       Chans - channel numbers, input as [6,8], defaults to 6 and 8
%OUTPUT:
%
% Created: 2016/05/25, 8 St. Mary's Street, Boston
%  Byron Price
% Updated: 2016/05/25
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

dataPoints = length(strobeData(1:2:end-1));
B = glmfit(1:dataPoints,strobeData(2:2:end)-strobeData(1:2:end-1),'Normal');
timeWindow = B(1);

Response = zeros(dataPoints,numChans);
timeFrames = round(timeWindow*sampleFreq);

delay = round(0.1*sampleFreq); % add delay after stimulus onset to account for
         % ~50ms delay in neuronal processing
for ii=1:numChans
    count = 1;
    for jj=2:2:length(strobeData)-1
        stimOnset = strobeData(jj);
        [~,index] = min(abs(timeStamps-stimOnset));
        Response(count,ii) = max(ChanData(index+delay:index+timeFrames,ii))-min(ChanData(index+delay:index+timeFrames,ii));
        count = count+1;
    end
end
cutOff = prctile(Response,99);

Indeces = cell(1,numChans);
figure();hold on;
for ii=1:numChans
        Indeces{ii} = find(Response(:,ii)>cutOff(ii));
        subplot(2,1,ii);plot(stimulusLocs(Indeces{ii},1),stimulusLocs(Indeces{ii},2),'*b','LineWidth',2);
end
hold off;

end