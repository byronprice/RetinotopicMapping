function [stimVals,centerMass,numChans] = MapRetinotopy(AnimalName,Date,yesNo)
% MapRetinotopy.m
%
%  Will take data from a retinotopic mapping experiment and extract the
%   retinotopy of the LFP recording electrode.
%INPUT: AnimalName - unique identifier for the animal as a number, e.g.
%            12345
%       Date - date of the experiment, e.g. 20160525
%       Optional:
%        yesNo - 1 if you are running this code as is, 0 if it is being run
%         through MapRetWrapper.m or you don't want to output and save the
%         figure for whatever reason
%OUTPUT: stimVals - values used to generate the imagesc figure
%        centerMass - for each channel, a vector with x position of the
%         retinotopic field's center of mass, y position, x standard
%         deviation and y standard deviation
%        numChans - number of channels for this setup, usually 2
%
% Created: 2016/05/25, 8 St. Mary's Street, Boston
%  Byron Price
% Updated: 2016/08/17
%  By: Byron Price

cd('~/CloudStation/ByronExp/Retino');
set(0,'DefaultFigureWindowStyle','docked');

% read in the .plx file
EphysFileName = sprintf('RetinoData%d_%d',Date,AnimalName); % no file identifier
                    % because MyReadall does that for us

if exist(strcat(EphysFileName,'.mat'),'file') ~= 2
    MyReadall(EphysFileName);
end

StimulusFileName = sprintf('RetinoStim%d_%d.mat',Date,AnimalName);
EphysFileName = strcat(EphysFileName,'.mat');
load(EphysFileName)
load(StimulusFileName)

if nargin < 3
    yesNo = 1;
end

sampleFreq = adfreq;

Chans = find(~cellfun(@isempty,allad));numChans = length(Chans);
strobeStart = 33;

% lowpass filter the data
dataLength = length(allad{1,Chans(1)});

ChanData = zeros(dataLength,numChans);
preAmpGain = 1;
for ii=1:numChans
    voltage = 1000.*((allad{1,Chans(ii)}).*SlowPeakV)./(0.5*(2^SlowADResBits)*adgains(Chans(ii))*preAmpGain);
    n = 30;
    lowpass = 100/(sampleFreq/2); % fraction of Nyquist frequency
    blo = fir1(n,lowpass,'low',hamming(n+1));
    ChanData(:,ii) = filter(blo,1,voltage);
end

timeStamps = 0:1/sampleFreq:dataLength/sampleFreq-1/sampleFreq;

if length(timeStamps) ~= dataLength
    display('Error: Review allad cell array and timing')
    return;
end
strobeTimes = tsevs{1,strobeStart};
stimLen = round((stimTime+0.2)*sampleFreq); % about 250 milliseconds
minWin = round(0.05*sampleFreq):1:round(0.15*sampleFreq);
maxWin = round(.1*sampleFreq):1:round(0.2*sampleFreq);
smoothKernel = 4;

% COLLECT DATA IN THE PRESENCE OF VISUAL STIMULI
Response = zeros(numChans,numStimuli,reps,stimLen);
meanResponse = zeros(numChans,numStimuli,stimLen);
for ii=1:numChans
    for jj=1:numStimuli
        stimStrobes = strobeTimes(svStrobed == jj);
        for kk=1:reps
            stimOnset = stimStrobes(kk);
            [~,index] = min(abs(timeStamps-stimOnset));
            temp = ChanData(index:index+stimLen-1,ii);
            Response(ii,jj,kk,:) = temp;
        end
        meanResponse(ii,jj,:) = smooth(mean(squeeze(Response(ii,jj,:,:)),1),smoothKernel);
        clear temp;
    end
end

% STATISTIC OF INTEREST is T = max - min(mean(LFP across stimulus repetitions)) 
% in the interval from 0 to ~ 0.3 seconds after an image is flashed on the 
% screen, this is a measure of the size of a VEP
dataStats = struct;
dataStats.mean = max(meanResponse(:,:,maxWin),[],3)-min(meanResponse(:,:,minWin),[],3);
dataStats.stdError = zeros(numChans,numStimuli);

% BOOTSTRAP FOR STANDARD ERROR OF STATISTIC IN PRESENCE OF VISUAL STIMULI
N = 2000; % number of bootstrap samples
for ii=1:numChans
    for jj=1:numStimuli
        Tboot = zeros(N,1);
        for kk=1:N
            indeces = random('Discrete Uniform',reps,[reps,1]);
            group = squeeze(Response(ii,jj,indeces,:));
            meanGroup = mean(group,1);
            Tboot(kk) = max(meanGroup(maxWin))-min(meanGroup(minWin));
        end
        dataStats.stdError(ii,jj) = std(Tboot);
    end
end

% BOOTSTRAP FOR 95% CONFIDENCE INTERVALS OF STATISTIC IN ABSENCE OF VISUAL STIMULI
%  AND STANDARD ERRORS
%  interspersed stimulus repetitions with holdTime seconds of a blank
%  screen
if exist('startPause','var') == 1
    holdTime = startPause; % used to do 120 second pause at the beginning,
                        % now do holdTime second pauses, usually 30 secs
    display('Old File');
end
noStimLen = holdTime*sampleFreq-stimLen*2;

baselineStats = struct;
baselineStats.prctile = zeros(numChans,1);
baselineStats.mean = zeros(numChans,1);
baselineStats.stdError = zeros(numChans,1);

for ii=1:numChans
    Tboot = zeros(N,1);
    pauseOnset = strobeTimes(svStrobed == 0);
    nums = length(pauseOnset);
    for jj=1:N
        indeces = random('Discrete Uniform',noStimLen,[reps,1]);
        temp = zeros(reps,stimLen);
        num = random('Discrete Uniform',nums);
        [~,index] = min(abs(timeStamps-pauseOnset(num)));
        for kk=1:reps
            temp(kk,:) = ChanData(index+indeces(kk):index+indeces(kk)+stimLen-1,ii);
        end
        meanTrace = mean(temp,1);
        Tboot(jj) = max(meanTrace(maxWin))-min(meanTrace(minWin));
    end
    %figure();histogram(Tboot);
    baselineStats.prctile(ii) = quantile(Tboot,1-1/100);
    baselineStats.mean(ii) = mean(Tboot);
    baselineStats.stdError(ii) = std(Tboot);
end

% for ii=1:numChans
%     figure();histogram(dataStat(ii,:));
%     hold on; plot(bootPrctile(ii)*ones(100,1),0:99,'LineWidth',2);
% end

% WALD TEST - VEP magnitude significantly greater in presence of a stimulus
%  than in the absence of a stimulus
significantStimuli = zeros(numChans,numStimuli);
alpha = 0.01; % 0.05/numStimuli
c = norminv(1-alpha,0,1);
for ii=1:numChans
    for jj=1:numStimuli
        W = (dataStats.mean(ii,jj)-baselineStats.mean(ii))/...
            sqrt(dataStats.stdError(ii,jj)^2+baselineStats.stdError(ii)^2);
        if W > c
            significantStimuli(ii,jj) = dataStats.mean(ii,jj); % or equals W itself
        end
    end    
end

centerMass = zeros(numChans,4);
Sigma = zeros(numChans,2,2);
for ii=1:numChans
    dataX = [];dataY = [];
    for jj=1:numStimuli
        
        dataX = [dataX;repmat(centerVals(jj,1),[round(significantStimuli(ii,jj)),1])];
        dataY = [dataY;repmat(centerVals(jj,2),[round(significantStimuli(ii,jj)),1])];
        % this step is fairly odd. To fit the 2D Gaussian in units of pixels, 
        % rather than in units of VEP magnitude, I make a distribution in 
        % each dimension by creating a vector of pixel values. If the VEP
        % magnitude at the location (1200,300), (x,y), was 250 microVolts,
        % then the dataX vector will have 250 repetitions of the value 1200
        % and the dataY vector will have 250 repetitions of the value 300.
        % So, the distribution ends up being weighted more heavily by pixel
        % values with strong VEPs. The values obtained by this method for
        % the center of the retinotopic map are identical to those obtained
        % by performing a center of mass calculation (center of mass
        % exactly like those done in physics, SUM x*m / SUM m , except that
        % m is the VEP magnitude instead of the mass).
    end
    data = [dataX,dataY];

    try
        mnPDF = fitgmdist(data,1);
        centerMass(ii,1) = mnPDF.mu(1);
        centerMass(ii,2) = mnPDF.mu(2);
        centerMass(ii,3) = mnPDF.Sigma(1,1);
        centerMass(ii,4) = mnPDF.Sigma(2,2);
        Sigma(ii,:,:) = mnPDF.Sigma;
    catch
        display(sprintf('\nError, Animal %d , Channel %d.\n',AnimalName,ii));
        centerMass(ii,:) = NaN;
        Sigma(ii,:,:) = NaN;
    end

end

stimVals = zeros(numChans,w_pixels,h_pixels);
x=1:w_pixels;
y=1:h_pixels;

xconv = stimLen/max(diff(sort(centerVals(:,1)))); % the max(diff(sort ...
                 % is equal to the width of the mapping stimulus (the width
                 % of the square that encloses the sinusoidal grating with
                 % overlain 2D Gaussian kernel) ... this value is
                 % equivalent to 2*Radius, which is output in the
                 % RetinoStim file, so I could use that. The only issue is
                 % that doing so would potentially preclude other types of
                 % stimuli from being analyzed by this code. As is, the
                 % code is fairly general to accept different types of
                 % mapping stimuli
yconv = 1000/max(diff(sort(centerVals(:,2)))); % for height of the stimulus

if yesNo == 1
    for ii=1:numChans
        h(ii) = figure;
    end
end
for ii=1:numChans
    if yesNo == 1 
        figure(h(ii));axis([0 w_pixels 0 h_pixels]);
        title(sprintf('VEP Retinotopy, Channel %d, Animal %d',ii,AnimalName));
        xlabel('Horizontal Screen Position (pixels)');ylabel('Vertical Screen Position (pixels)');
        hold on;
    end
    for jj=1:numStimuli
%         stimVals(ii,tempx-Radius:tempx+Radius,tempy-Radius:tempy+Radius) = significantStimuli(ii,jj);
        if yesNo == 1
            plot(((1:1:stimLen)./xconv+centerVals(jj,1)-0.5*max(diff(sort(centerVals(:,1))))),...
                (squeeze(meanResponse(ii,jj,:))'./yconv+centerVals(jj,2)),'k','LineWidth',2);
        end
    end
    if isnan(centerMass(ii,:)) ~= 1
        obj = gmdistribution(centerMass(ii,1:2),squeeze(Sigma(ii,:,:)));
        combos = zeros(w_pixels*h_pixels,2);
        count = 1;
        for kk=1:w_pixels
            for ll=h_pixels:-1:1
                %             stimVals(ii,kk,ll) = pdfFun(kk,ll);
                combos(count,:) = [kk,ll];
                count = count+1;
            end
        end
        temp = reshape(pdf(obj,combos),[h_pixels,w_pixels]);
        temp = flipud(temp)';
        stimVals(ii,:,:) = (temp./(max(max(temp)))).*max(significantStimuli(ii,:));
        if yesNo == 1
            imagesc(x,y,squeeze(stimVals(ii,:,:))','AlphaData',0.5);set(gca,'YDir','normal');w=colorbar;
            ylabel(w,'VEP Magnitude (\muV)');colormap('jet');
            hold off;
        end
    end
end
if yesNo == 1
    Channel = input('Type the channel that looks best (as a number, e.g. 1): ');
    savefig(h,sprintf('RetinoMap%d_%d.fig',Date,AnimalName));
    %print(h,'-depsc','filename');
end

save(sprintf('RetinoMap%d_%d.mat',Date,AnimalName),'numChans',...
    'centerVals','significantStimuli','centerMass','stimVals',...
    'Sigma','Response','Channel','dataStats','baselineStats');

set(0,'DefaultFigureWindowStyle','normal');
% obj = gmdistribution(centerMass(Channel,1:2),squeeze(Sigma(Channel,:,:)));
% figure();
% h = ezcontour(@(x,y) pdf(obj,[x y]),[0 w_pixels,0 h_pixels]);
end
