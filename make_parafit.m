%para: Z,D,mu,theta,alpha1,alpha2,...,alphaN,beta1,...,betaN

load statecodes.mat

parafit=zeros(6,100);

num_loc=size(statecodes,1);


%define alphamaps
alphamaps=4+(1:num_loc)';
%define betamap
betamap=4+num_loc+(1:num_loc)';


Zlow=2;Zup=5;%latency period
Dlow=2;Dup=5;%infectious period
mulow=0.2;muup=0.45;%relative transmissibility
thetalow=0;thetaup=0.02;%movement factor
alphalow=0.025;alphaup=0.60;%reporting rate
betalow=0.2;betaup=5; %transmission rate


paramin=[Zlow;Dlow;mulow;thetalow;ones(num_loc,1)*alphalow;ones(num_loc,1)*betalow];
paramax=[Zup;Dup;muup;thetaup;ones(num_loc,1)*alphaup;ones(num_loc,1)*betaup];


parafit(1,:)= squeeze(Zlow + (Zup-Zlow)*rand(100,1));
parafit(2,:)= squeeze(Dlow + (Dup-Dlow)*rand(100,1));
parafit(3,:)= squeeze(mulow + (muup-mulow)*rand(100,1));
parafit(4,:)= squeeze(thetalow + (thetaup-thetalow)*rand(100,1));
parafit(5,:)= squeeze(alphalow + (alphaup-alphalow)*rand(100,1));
parafit(6,:)= squeeze(betalow + (betaup-betalow)*rand(100,1)); %beta uniformally distributed

% %beta normally dist
% parafit(6,:)=squeeze(normrnd((betaup-betalow)/2, 0.75, [1, 100])); 
% %out of bound values back inside randomly
% parafit(6,(parafit(6,:) < betalow)) = betalow+(betaup-betalow)*rand(size( parafit(6,(parafit(6,:) < betalow))));
% parafit(6,(parafit(6,:) > betaup)) = betalow+(betaup-betalow)*rand(size(parafit(6,(parafit(6,:) > betaup))));


clearvars -except Dlow Dup Zlow Zup thetalow thetaup mulow muup alphalow alphaup betalow betaup ... 
    paramin paramax parafit alphamaps betamap

save parafit_vars.mat
