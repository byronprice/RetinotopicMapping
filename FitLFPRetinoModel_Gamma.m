function [finalParameters,fisherInfo,ninetyfiveErrors,conclusion] = FitLFPRetinoModel_Gamma(Response,xaxis,yaxis)
%FitLFPRetinoModel_Gamma.m
%   Use data from LFP retinotopic mapping experiment to fit a non-linear
%    model of that retinotopy (data is maximum LFP magnitude in window 
%    from 150 to 250msec minus minimum magnitude in window from 50 to
%    120 msec after stimulus presentation, assumes a
%    Gamma likelihood)
%

%Created: 2017/02/22, 24 Cummington Mall, Boston
% Byron Price
%Updated: 2017/03/13
% By: Byron Price

%  model has 7 parameters, defined by vector p
%  data ~ gamma(k,theta), 
%    where the mean of the data follows
%     mean = (p(1)*exp(-(xpos-p(2)).^2./(2*p(4)*p(4))-(ypos-p(3)).^2./(2*p(5)*p(5)))+p(6));
%    and mean = k*theta
%        var = k*theta^2
%
%      to fit, however, I use a gamma(mean,dispersion) parameterization, so
%       the last parameter in the fit is phi, the dispersion.
%      With phi, the variance = phi*mu^2, so we can solve for k and theta
%      as theta = variance/mu = phi*mu and k = 1/phi

% parameter estimates are constrained to a reasonable range of values
Bounds = [0,1000;min(xaxis)-50,max(xaxis)+50;min(yaxis)-50,max(yaxis)+50;1,1000;1,1000;0,1000;1e-2,100];
numChans = size(Response,1);

numParameters = 7;
   
finalParameters = zeros(numChans,numParameters);
fisherInfo = zeros(numChans,numParameters,numParameters);
ninetyfiveErrors = zeros(numChans,numParameters);
conclusion = zeros(numChans,1);
numRepeats = 10000;
maxITER = 100;
likelyTolerance = 1e-3;
gradientTolerance = 1e-5;

for zz=1:numChans
%     display(sprintf('Running Data for Channel %d...',zz));

    Data = Response{zz};
    reps = size(Data,1);
    
    flashPoints = Data(:,1:2);
    vepMagnitude = abs(Data(:,3));
    
    h = ones(numParameters,1)./100;
    bigParameterVec = zeros(numParameters,numRepeats);
    bigLikelihood = zeros(numRepeats,1);
    % repeat gradient ascent from a number of different starting
    %  positions
    
    phat = gamfit(vepMagnitude);medianVal = median(vepMagnitude);
%     meanVal = mean(vepMagnitude);modeVal = (phat(1)-1)*phat(2);
    parfor repeats = 1:numRepeats
        parameterVec = zeros(numParameters,maxITER);
        logLikelihood = zeros(reps,maxITER);

        proposal = [2.5,78;5,200;2.6,152;6.7,38.6;5.9,40.3;8.6,43.1;1.5,0.5];
        for ii=1:numParameters-2
              parameterVec(ii,1) = gamrnd(proposal(ii,1),proposal(ii,2));
        end
        parameterVec(6,1) = medianVal+normrnd(0,50);
        parameterVec(7,1) = 1/phat(1)+normrnd(0,0.1);
        
        parameterVec(:,1) = max(Bounds(:,1),min(parameterVec(:,1),Bounds(:,2)));
        
        [logLikelihood(:,1)] = GetLikelihood(reps,parameterVec(:,1),vepMagnitude,flashPoints);

        check = 1;
        iter = 1;
        lambda = 1000;
        update = ones(numParameters,1);
%         figure();scatter(iter,sum(logLikelihood(:,iter)));pause(1);hold on;
        try
            % for each starting position, do maxITER iterations
            while abs(check) > likelyTolerance && iter < maxITER && sum(abs(update)) > gradientTolerance
                [Jacobian,tempLikely] = GetJacobian(reps,parameterVec(:,iter),vepMagnitude,flashPoints,numParameters,h,logLikelihood(:,iter));
                H = Jacobian'*Jacobian;
                update = pinv(H+lambda.*diag(diag(H)))*Jacobian'*((logLikelihood(:,iter)-tempLikely)/h(1)); % or /h(1)
                
                tempParams = parameterVec(:,iter)+update;
                
                tempParams = max(Bounds(:,1),min(tempParams,Bounds(:,2)));
                
                [tempLikely] = GetLikelihood(reps,tempParams,vepMagnitude,flashPoints);
                check = sum(tempLikely)-sum(logLikelihood(:,iter));
                if check <= 0
                    parameterVec(:,iter+1) = parameterVec(:,iter);
                    logLikelihood(:,iter+1) = logLikelihood(:,iter);
                    lambda = min(lambda*10,1e10);
                    check = 1;
% %                     display('no');
% %                 elseif check == 0
% %                     check = 1;
%                     tempParams = parameterVec(:,iter)+normrnd(0,10,[numParameters,1]);
%                     tempParams = max(Bounds(:,1),min(tempParams,Bounds(:,2)));
%                     logLikelihood(:,iter+1) = GetLikelihood(reps,tempParams,vepMagnitude,flashPoints);
%                     lambda = min(lambda*10,1e10);
                else
                    parameterVec(:,iter+1) = tempParams;
                    logLikelihood(:,iter+1) = tempLikely;
                    lambda = max(lambda/10,1e-10);
                end
                iter = iter+1;%scatter(iter,sum(logLikelihood(:,iter)));pause(0.01);
            end
            
            maxLikelies = sum(logLikelihood(:,1:iter),1);
            [bigLikelihood(repeats),index] = max(maxLikelies);
            bigParameterVec(:,repeats) = parameterVec(:,index);
        catch
            
        end
    end
    logicalInds = bigLikelihood~=0;
    [maxVal,index] = max(bigLikelihood(logicalInds));
    
    tempBigParams = bigParameterVec(:,logicalInds);
    finalParameters(zz,:) = tempBigParams(:,index)';
    
    allInds = bigLikelihood(logicalInds) == maxVal;
    sum(allInds)
    [fisherInfo(zz,:,:),ninetyfiveErrors(zz,:)] = getFisherInfo(finalParameters(zz,:),numParameters,h,reps,vepMagnitude,flashPoints);
    
    totalError = sum(ninetyfiveErrors(zz,:));
    test = finalParameters(zz,:)-ninetyfiveErrors(zz,:);
    
    test2 = repmat(finalParameters(zz,:)',[1,2])-Bounds;
    test2([2,3,6],:) = [];
    check = sum(sum(test2==0));
    if totalError > 2000 || test(1) < 0 || check > 0
       conclusion(zz) = 0;
    else
        conclusion(zz) = 1;
    end
    display(zz);
    display(conclusion(zz));
    display(finalParameters(zz,:));
    display(ninetyfiveErrors(zz,:));
end
end

function [Jacobian,tempLikely] = GetJacobian(reps,parameterVec,vepMagnitude,flashPoints,numParameters,h,prevLikely)
Jacobian = zeros(reps,numParameters);
tempLikely = zeros(reps,1);
for kk=1:reps
    for jj=1:numParameters
       tempParams = parameterVec;tempParams(jj) = tempParams(jj)+h(jj);
       mu = tempParams(1)*exp(-((flashPoints(kk,1)-tempParams(2)).^2)./(2*tempParams(4).^2)-...
        ((flashPoints(kk,2)-tempParams(3)).^2)./(2*tempParams(5).^2))+tempParams(6);
       likelihood = (-vepMagnitude(kk)/mu-log(mu))/tempParams(7)-log(tempParams(7))/tempParams(7)+...
           (1/tempParams(7)-1)*log(vepMagnitude(kk))-log(gamma(1/tempParams(7)));
       Jacobian(kk,jj) = (likelihood-prevLikely(kk))/h(jj);
    end
    tempParams = parameterVec+h;
    mu = tempParams(1)*exp(-((flashPoints(kk,1)-tempParams(2)).^2)./(2*tempParams(4).^2)-...
        ((flashPoints(kk,2)-tempParams(3)).^2)./(2*tempParams(5).^2))+tempParams(6);
    
    tempLikely(kk) = (-vepMagnitude(kk)/mu-log(mu))/tempParams(7)-log(tempParams(7))/tempParams(7)+...
           (1/tempParams(7)-1)*log(vepMagnitude(kk))-log(gamma(1/tempParams(7)));
end
end


function [loglikelihood] = GetLikelihood(reps,parameterVec,vepMagnitude,flashPoints)
loglikelihood = zeros(reps,1);
for kk=1:reps
    mu = parameterVec(1)*exp(-((flashPoints(kk,1)-parameterVec(2)).^2)./(2*parameterVec(4).^2)-...
        ((flashPoints(kk,2)-parameterVec(3)).^2)./(2*parameterVec(5).^2))+parameterVec(6);
    loglikelihood(kk) = (-vepMagnitude(kk)/mu-log(mu))/parameterVec(7)-log(parameterVec(7))/parameterVec(7)+...
           (1/parameterVec(7)-1)*log(vepMagnitude(kk))-log(gamma(1/parameterVec(7)));
end
end

function [fisherInfo,errors] = getFisherInfo(parameters,numParameters,h,reps,peakNegativity,flashPoints)
fisherInfo = zeros(numParameters,numParameters);
errors = zeros(1,numParameters);

% h = h./100;
% the observed fisher information matrix 
for jj=1:numParameters
    for kk=jj:numParameters
        firstParam = jj;secondParam = kk;
        deltaX = h(firstParam);deltaY = h(secondParam);
        
        if firstParam ~= secondParam
            parameterVec = parameters;parameterVec(firstParam) = parameterVec(firstParam)+deltaX;
            parameterVec(secondParam) = parameterVec(secondParam)+deltaY;
            likelyplusplus = GetLikelihood(reps,parameterVec,peakNegativity,flashPoints);
            
            parameterVec = parameters;parameterVec(firstParam) = parameterVec(firstParam)+deltaX;
            parameterVec(secondParam) = parameterVec(secondParam)-deltaY;
            likelyplusminus = GetLikelihood(reps,parameterVec,peakNegativity,flashPoints);
            
            parameterVec = parameters;parameterVec(firstParam) = parameterVec(firstParam)-deltaX;
            parameterVec(secondParam) = parameterVec(secondParam)+deltaY;
            likelyminusplus = GetLikelihood(reps,parameterVec,peakNegativity,flashPoints);
            
            parameterVec = parameters;parameterVec(firstParam) = parameterVec(firstParam)-deltaX;
            parameterVec(secondParam) = parameterVec(secondParam)-deltaY;
            likelyminusminus = GetLikelihood(reps,parameterVec,peakNegativity,flashPoints);
            
            fisherInfo(jj,kk) = -(sum(likelyplusplus)-sum(likelyplusminus)-sum(likelyminusplus)+sum(likelyminusminus))./(4*deltaX*deltaY);
        else
            likely = GetLikelihood(reps,parameters,peakNegativity,flashPoints);
            
            parameterVec = parameters;parameterVec(firstParam) = parameterVec(firstParam)-deltaX;
            likelyminus = GetLikelihood(reps,parameterVec,peakNegativity,flashPoints);
            
            parameterVec = parameters;parameterVec(firstParam) = parameterVec(firstParam)+deltaX;
            likelyplus = GetLikelihood(reps,parameterVec,peakNegativity,flashPoints);
            
            fisherInfo(jj,kk) = -(sum(likelyminus)-2*sum(likely)+sum(likelyplus))./(deltaX*deltaX);
        end
    end
end

transpose = fisherInfo';
for ii=1:numParameters
    for jj=1:ii-1
        fisherInfo(ii,jj) = transpose(ii,jj);
    end
end

inverseFisherInfo = inv(fisherInfo);
for ii=1:numParameters
    errors(ii) = sqrt(inverseFisherInfo(ii,ii));
end

if isreal(errors) == 0
    temp = sqrt(errors.*conj(errors));
    errors = 1.96.*temp;
elseif isreal(errors) == 1
    errors = 1.96.*errors;
end
end


