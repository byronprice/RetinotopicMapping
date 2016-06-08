function [] = MapRetinotopyCallaway(AnimalName,Date,Chans)
% MapRetinotopyCallaway.m
%
%  Will take data from a retinotopic mapping experiment and extract the
%   retinotopy of the LFP recording electrode. The stimulus used here is
%   the periodic drifting bar with flashing counter-phase checkerboard from
%   the file RetinotopyCallaway.m
%     Must have the Matlab Offline Files SDK on the current path
%
%INPUT: AnimalName - unique identifier for the animal as a number, e.g.
%            12345
%       Date - date of the experiment input as a number yearMonthDay, 
%            e.g. 20160525
%       Chans - channel numbers, input as [6,8], defaults to 6 and 8
%OUTPUT: a plot
%
% Created: 2016/05/31, 24 Cummington, Boston
%  Byron Price
% Updated: 2016/06/08
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

%totalAD = size(allad,2);
%totalSEVS = size(tsevs,2);

x = find(~cellfun(@isempty,allad));
channelStart = x(1);

x = find(~cellfun(@isempty,tsevs));
strobeStart = x(1);

dataLength = length(allad{1,strobeStart+Chans(1)-1});
numChans = length(Chans);
ChanData = zeros(dataLength,numChans);
for ii=1:numChans
    ChanData(:,ii) = allad{1,strobeStart+Chans(ii)-1};
end
%figure();subplot(2,1,1);plot(ChanData(:,1));subplot(2,1,2);plot(ChanData(:,2));
timeStamps = 0:1/sampleFreq:dataLength/sampleFreq-1/sampleFreq;

if length(timeStamps) ~= dataLength
    display('Error: Review allad cell array and timing')
    return;
end
strobeData = tsevs{1,strobeStart};

pixels = [2*w_pixels,2*h_pixels];
stimLength = round((pixels/driftSpeed)*sampleFreq/2)*2;
stimPosition = struct('Horz',[linspace(1,w_pixels,stimLength(1)/2),linspace(w_pixels,1,stimLength(1)/2)],...
    'Vert',[linspace(1,h_pixels,stimLength(2)/2),linspace(h_pixels,1,stimLength(2)/2)]);

%delay = round(0.04*sampleFreq); % 50 ms delay
Response = struct('Horz',zeros(stimLength(1),numChans),'Vert',zeros(stimLength(2),numChans));

for ii=1:numChans
    for jj=1:2
        temp = 0;
        for kk=1:reps
            if jj == 1
                check = kk;
            else
                check = kk+reps;
            end
            stimOnset = strobeData(check);
            [~,index] = min(abs(timeStamps-stimOnset));
            temp = temp+ChanData(index:index+stimLength(jj)-1,ii);
        end
        if jj == 1
            Response.Horz(:,ii) = (temp./reps).^2;
        else
            Response.Vert(:,ii) = (temp./reps).^2;
        end
    end
end

figure();
subplot(2,2,1);plot(stimPosition.Horz(1:stimLength(1)/2),Response.Horz(1:stimLength(1)/2,1));title('Horizontal Stimulus Right');
subplot(2,2,2);plot(stimPosition.Vert(1:stimLength(2)/2),Response.Vert(1:stimLength(2)/2,1));title('Vertical Stimulus Up');
subplot(2,2,3);plot(stimPosition.Horz(1:stimLength(1)/2),flipud(Response.Horz(stimLength(1)/2+1:end,1)));title('Horizontal Stimulus Left');
subplot(2,2,4);plot(stimPosition.Vert(1:stimLength(2)/2),flipud(Response.Vert(stimLength(2)/2+1:end,1)));title('Vertical Stimulus Down');

end
