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
% Updated: 2016/06/17
%  By: Byron Price

% read in the .plx file
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
newFs = 5;
downSampleRate = sampleFreq/newFs;


% tsevs are the strobed times of stimulus onset, then offset
%  Onset at tsevs{1,33}(2), offset at tsevs{1,33}(3), onset at
%  tsevs{1,33}(4), offset at 5, etc.
% allad contains the continuous data from each channel, which appear to be
%  recorded at 1000 Hz rather than 40,000

%totalAD = size(allad,2);
%totalSEVS = size(tsevs,2);

%x = find(~cellfun(@isempty,tsevs));
strobeStart = 33;

% lowpass filter the data
dataLength = length(allad{1,strobeStart+Chans(1)-1});
numChans = length(Chans);
ChanData = zeros(dataLength,numChans);
for ii=1:numChans
    temp = smooth(allad{1,strobeStart+Chans(ii)-1},0.1*sampleFreq);
    n = 30;
    lowpass = 1/downSampleRate; % fraction of Nyquist frequency
    blo = fir1(n,lowpass,'low',hamming(n+1));
    ChanData(:,ii) = filter(blo,1,temp);
    %lowfreq = smooth(ChanData(:,ii),dataLength/(4*reps));
    %figure();plot(ChanData(:,ii));hold on;plot(lowfreq,'r');
    %hold off; figure();plot(ChanData(:,ii)-lowfreq)
end


timeStamps = 0:1/sampleFreq:dataLength/sampleFreq-1/sampleFreq;

if length(timeStamps) ~= dataLength
    display('Error: Review allad cell array and timing')
    return;
end
strobeData = tsevs{1,strobeStart};

%figure();plot(timeStamps,ChanData(:,1));hold on;
%plot(strobeData,ones(length(strobeData))*-250,'*r');

stimFreq = 1/driftTime;
stimLength = round(driftTime*sampleFreq/2)*2;
stimWidth = [Width/w_pixels,Width/h_pixels].*stimLength;

stimPosition = cell(1,4);
stimPosition{1} = linspace(1,w_pixels,stimLength);
stimPosition{2} = linspace(w_pixels,1,stimLength);
stimPosition{3} = linspace(1,h_pixels,stimLength);
stimPosition{4} = linspace(h_pixels,1,stimLength);

delay = round(0*sampleFreq); % 0 ms delay
Response = cell(1,4);
Response{1} = zeros(stimLength*reps,numChans);
Response{2} = zeros(stimLength*reps,numChans);
Response{3} = zeros(stimLength*reps,numChans);
Response{4} = zeros(stimLength*reps,numChans);

for ii=1:numChans
    for jj=1:4
        check = (jj-1)*reps+1:jj*reps;
        for kk=1:reps
            stimLoc = (kk-1)*stimLength+1:kk*stimLength;
     
            stimOnset = strobeData(check(kk));
            [~,index] = min(abs(timeStamps-stimOnset));
            Response{jj}(stimLoc,ii) = ChanData(index+delay:index+delay+stimLength-1,ii);
        end
        Response{jj}(:,ii) = Response{jj}(:,ii);
    end
end
%figure();plot(Response{1}(:,1));

Fourier = zeros(4,numChans);
PhaseResponse = zeros(2,numChans);
AmpResponse = zeros(2,numChans);
for ii=1:numChans
    for jj=1:4
        L = stimLength*reps;
        n = 2^nextpow2(L); % pad signal with trailing zeros
        Y = fft(Response{jj}(:,ii),n);
        f = sampleFreq*(0:(n/2))/n;
        Y = Y(1:n/2+1)./n;
        %figure();plot(f,log(abs(Y)));
        [~,index] = min(abs(f-stimFreq));
 
        Fourier(jj,ii) = Y(index);
    end
    PhaseResponse(1,ii) = angle(Fourier(1,ii)/Fourier(2,ii));
    PhaseResponse(2,ii) = angle(Fourier(3,ii)/Fourier(4,ii));
    AmpResponse(1,ii) = abs(Fourier(1,ii)/Fourier(2,ii));
    AmpResponse(2,ii) = abs(Fourier(3,ii)/Fourier(4,ii));
end

%phase 0 peak at pi/2
%phase pi/4 peak at pi/4 (shifts left by pi/4)
%phase -pi/4 peak at 3pi/4 (shifts right by pi/4)
CenterPoints = zeros(2,numChans);
for ii=1:numChans
    for jj=1:2
        if jj == 1
            CenterPoints(jj,ii) = round(((PhaseResponse(jj,ii)+pi/2)/(2*pi))*w_pixels);
        elseif jj == 2
            CenterPoints(jj,ii) = round(((PhaseResponse(jj,ii)+pi/2)/(2*pi))*h_pixels);
        end
    end
end
fileName = strcat('RetinoMap_',num2str(AnimalName));
save(fileName,'CenterPoints','Width','w_pixels','h_pixels')

figure();
hold on;
xlim([0 w_pixels])
ylim([0 h_pixels])
for ii=1:numChans
    plot(CenterPoints(1,ii),CenterPoints(2,ii),'*')
end
end