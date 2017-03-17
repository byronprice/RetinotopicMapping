function [finalParameters,fisherInfo,ninetyfiveErrors,result,Deviance,chi2p] = FitLFPRetinoModel_Gamma(Response,xaxis,yaxis,numRepeats)
%FitLFPRetinoModel_Gamma.m
%   Use data from LFP retinotopic mapping experiment to fit a non-linear
%    model of that retinotopy (data is maximum LFP magnitude in window 
%    from 150 to 250msec minus minimum magnitude in window from 50 to
%    120 msec after stimulus presentation, assumes a
%    Gamma likelihood)
%

%Created: 2017/02/22, 24 Cummington Mall, Boston
% Byron Price
%Updated: 2017/03/16
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
Bounds = [0,2000;min(xaxis)-50,max(xaxis)+50;min(yaxis)-50,max(yaxis)+50;1,1000;1,1000;0,1000;-1,1;1e-2,100];
numChans = size(Response,1);

numParameters = 8;
   
finalParameters = zeros(numChans,numParameters);
fisherInfo = zeros(numChans,numParameters,numParameters);
ninetyfiveErrors = zeros(numChans,numParameters);
result = zeros(numChans,1);
chi2p = zeros(numChans,1);
Deviance = zeros(numChans,1);

% numRepeats = 1e4;
maxITER = 100;
likelyTolerance = 1e-6;
gradientTolerance = 1e-6;

for zz=1:numChans
%     display(sprintf('Running Data for Channel %d...',zz));

    Data = Response{zz};
    reps = size(Data,1);
    
    flashPoints = Data(:,1:2);
    vepMagnitude = abs(Data(:,3));
    
    h = ones(numParameters,1)./1000;
    bigParameterVec = zeros(numParameters-1,numRepeats);
    bigDeviance = zeros(numRepeats,1);
    % repeat gradient ascent from a number of different starting
    %  positions
    
%     phat = gamfit(vepMagnitude);
    medianVal = median(vepMagnitude);
%     meanVal = mean(vepMagnitude);modeVal = (phat(1)-1)*phat(2);
    parfor repeats = 1:numRepeats
        parameterVec = zeros(numParameters-1,maxITER);
        totalDeviance = zeros(maxITER,1);
        
        proposal = [2.5,78;5,200;2.6,152;6.7,38.6;5.9,40.3;8.6,43.1;0,0.25;1.5,0.5];
        for ii=1:numParameters-3
              parameterVec(ii,1) = gamrnd(proposal(ii,1),proposal(ii,2));
        end
        parameterVec(6,1) = medianVal+normrnd(0,50);
        parameterVec(7,1) = normrnd(proposal(7,1),proposal(7,2));
        
        parameterVec(:,1) = max(Bounds(1:numParameters-1,1),min(parameterVec(:,1),Bounds(1:numParameters-1,2)));
        
        deviance = GetDeviance(reps,parameterVec,vepMagnitude,flashPoints);
        mu = GetMu(reps,parameterVec,flashPoints);
        
        totalDeviance(1) = sum(deviance);

        check = 1;
        iter = 1;
        lambda = 1000;
        update = ones(numParameters,1);
%         figure();scatter(iter,totalDeviance(1));pause(1);hold on;
        try
            % for each starting position, do maxITER iterations
            
            while abs(check) > likelyTolerance && iter < maxITER && sum(abs(update)) > gradientTolerance
                [Jacobian] = GetJacobian(reps,parameterVec(:,iter),flashPoints,numParameters-1,h,mu);
                H = Jacobian'*Jacobian;
                update = pinv(H+lambda.*diag(diag(H)))*Jacobian'*(vepMagnitude-mu);
                tempParams = parameterVec(:,iter)+update;
            
                tempParams = max(Bounds(1:numParameters-1,1),min(tempParams,Bounds(1:numParameters-1,2)));
            
                [tempMu] = GetMu(reps,tempParams,flashPoints);
               
                totalDeviance(iter+1) = sum(2*(log(tempMu./vepMagnitude)+(vepMagnitude-tempMu)./tempMu));
                check = diff(totalDeviance(iter:iter+1));
                if check >= 0
                    parameterVec(:,iter+1) = parameterVec(:,iter);
                    lambda = min(lambda*10,1e10);
                    check = 1;
                    totalDeviance(iter+1) = totalDeviance(iter);
                else
                    parameterVec(:,iter+1) = tempParams;
                    mu = tempMu;
                    lambda = max(lambda/10,1e-10);
                end
                iter = iter+1;%scatter(iter,totalDeviance(iter));pause(0.01);
            end
            
            [bigDeviance(repeats),index] = min(totalDeviance(1:iter));
            bigParameterVec(:,repeats) = parameterVec(:,index);
        catch
            
        end
    end
    logicalInds = bigDeviance~=0;
    [minimumDev,index] = min(bigDeviance(logicalInds));
    
    dispersionEstimate = minimumDev/(reps-numParameters);
    tempBigParams = bigParameterVec(:,logicalInds);
    finalParameters(zz,1:numParameters-1) = tempBigParams(:,index)';
    finalParameters(zz,end) = dispersionEstimate;
    
    parameterVec = zeros(maxITER,numParameters);
    logLikelihood = zeros(reps,maxITER);
    
    parameterVec(1,:) = finalParameters(zz,:);
    [logLikelihood(:,1)] = GetLikelihood(reps,parameterVec(1,:),vepMagnitude,flashPoints);
    check = 1;iter = 1;lambda = 10;
    while abs(check) > likelyTolerance && iter < maxITER*numParameters
        for jj=1:numParameters
            tempParameterVec = parameterVec(iter,:);
            tempParameterVec(jj) = tempParameterVec(jj)+h(jj);
            [gradLikelihoodplus] = GetLikelihood(reps,tempParameterVec,vepMagnitude,flashPoints);
            
            move = sign((sum(gradLikelihoodplus)-sum(logLikelihood(:,iter)))).*h(jj);
        
            tempParams = parameterVec(iter,:);
            tempParams(jj) = tempParams(jj)+move;

            tempParams = max(Bounds(:,1)',min(tempParams,Bounds(:,2)'));
        
            tempLikelihood = GetLikelihood(reps,tempParams,vepMagnitude,flashPoints);
            check = sum(tempLikelihood)-sum(logLikelihood(:,iter));
        
            if check <= 0
                lambda = lambda/10;
                parameterVec(iter+1,:) = parameterVec(iter,:);
                logLikelihood(:,iter+1) = logLikelihood(:,iter);
                check = 1;
            else
                parameterVec(iter+1,:) = tempParams;
                logLikelihood(:,iter+1) = tempLikelihood;
            end
            iter = iter+1;
        end
    end
    [~,index] = max(sum(logLikelihood(:,1:iter),1));
    finalParameters(zz,:) = parameterVec(index,:);
    
    
    [fisherInfo(zz,:,:),ninetyfiveErrors(zz,:)] = getFisherInfo(finalParameters(zz,:),numParameters,h,reps,vepMagnitude,flashPoints);
    
    [deviance] = GetDeviance(reps,finalParameters(zz,:),vepMagnitude,flashPoints);
    Deviance(zz) = sum(deviance);
    chi2p(zz) = 1-chi2cdf(Deviance(zz)/finalParameters(zz,end),reps-numParameters);
    
    totalError = sum(ninetyfiveErrors(zz,:));
    test = finalParameters(zz,:)-ninetyfiveErrors(zz,:);
    
    test2 = repmat(finalParameters(zz,:)',[1,2])-Bounds;
    test2([2,3,6],:) = [];
    check = sum(sum(test2==0));
    if totalError > 2000 || test(1) < 0 || check > 0 %|| test(4) < 0 || test(5) < 0
       result(zz) = 0;
    else
        result(zz) = 1;
    end
    display(zz);
    display(result(zz));
    display(chi2p(zz));
    display(finalParameters(zz,:));
    display(ninetyfiveErrors(zz,:));
end
end

function [Jacobian] = GetJacobian(reps,parameterVec,flashPoints,numParameters,h,mu)
Jacobian = zeros(reps,numParameters);
for kk=1:reps
    for jj=1:numParameters
       tempParams = parameterVec;tempParams(jj) = tempParams(jj)+h(jj);
       tempMu = tempParams(1)*exp(-((flashPoints(kk,1)-tempParams(2)).^2)./(2*tempParams(4).^2)-...
        ((flashPoints(kk,2)-tempParams(3)).^2)./(2*tempParams(5).^2)-...
        tempParams(7)*(flashPoints(kk,1)-tempParams(2))*(flashPoints(kk,2)-tempParams(3))/(2*tempParams(4)*tempParams(5)))+tempParams(6);

       Jacobian(kk,jj) = (tempMu-mu(kk))/h(jj);
    end
end
end


function [loglikelihood] = GetLikelihood(reps,parameterVec,vepMagnitude,flashPoints)
loglikelihood = zeros(reps,1);
for kk=1:reps
    mu = parameterVec(1)*exp(-((flashPoints(kk,1)-parameterVec(2)).^2)./(2*parameterVec(4).^2)-...
        ((flashPoints(kk,2)-parameterVec(3)).^2)./(2*parameterVec(5).^2)-...
        parameterVec(7)*(flashPoints(kk,1)-parameterVec(2))*(flashPoints(kk,2)-parameterVec(3))/(2*parameterVec(4)*parameterVec(5)))+parameterVec(6);
    loglikelihood(kk) = (-vepMagnitude(kk)/mu-log(mu))/parameterVec(8)-log(parameterVec(8))/parameterVec(8)+...
           (1/parameterVec(8)-1)*log(vepMagnitude(kk))-log(gamma(1/parameterVec(8)));
end
end

function [mu] = GetMu(reps,parameterVec,flashPoints)
mu = zeros(reps,1);
for kk=1:reps
    mu(kk) = parameterVec(1)*exp(-((flashPoints(kk,1)-parameterVec(2)).^2)./(2*parameterVec(4).^2)-...
        ((flashPoints(kk,2)-parameterVec(3)).^2)./(2*parameterVec(5).^2)-...
        parameterVec(7)*(flashPoints(kk,1)-parameterVec(2))*(flashPoints(kk,2)-parameterVec(3))/(2*parameterVec(4)*parameterVec(5)))+parameterVec(6);
end

end

function [deviance] = GetDeviance(reps,parameterVec,vepMagnitude,flashPoints)
deviance = zeros(reps,1);

for kk=1:reps
    mu = parameterVec(1)*exp(-((flashPoints(kk,1)-parameterVec(2)).^2)./(2*parameterVec(4).^2)-...
        ((flashPoints(kk,2)-parameterVec(3)).^2)./(2*parameterVec(5).^2)-...
        parameterVec(7)*(flashPoints(kk,1)-parameterVec(2))*(flashPoints(kk,2)-parameterVec(3))/(2*parameterVec(4)*parameterVec(5)))+parameterVec(6);
    deviance(kk) =  2*(log(mu/vepMagnitude(kk))+(vepMagnitude(kk)-mu)/mu);
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
