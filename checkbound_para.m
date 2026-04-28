function para = checkbound_para(para,paramax,paramin,para_ori,alphamaps,betamap,flact_checkpara)
%check parameter bound



for i = 1:length(alphamaps) % length(alphamaps)==num_loc

    %out-of-bound %alpha get sampled across the intial spread times a factor
    mina = max(min(para_ori(alphamaps(i),:))*(1-flact_checkpara),paramin(alphamaps(i)));
    maxa = min(max(para_ori(alphamaps(i),:))*(1+flact_checkpara),paramax(alphamaps(i)));
    
    dim1 = size(para(alphamaps(i),para(alphamaps(i),:)<paramin(alphamaps(i))));
    para(alphamaps(i),para(alphamaps(i),:)<paramin(alphamaps(i)))=rand(dim1).*(maxa-mina) + mina;

    dim2 = size(para(alphamaps(i),para(alphamaps(i),:)>paramax(alphamaps(i))));
    para(alphamaps(i),para(alphamaps(i),:)>paramax(alphamaps(i)))=rand(dim2).*(maxa-mina) + mina;


    %out-of-bound beta are resampled across the ensamble at that time times a factor

    %min of the \beta above betalow, or betalow if they are all below
    minb = max(min(para(betamap(i),para(betamap(i),:)>paramin(betamap(i))))*(1-flact_checkpara),paramin(betamap(i)));
    if isempty(minb) 
        minb=paramin(betamap(i));
    end
    %max of the \beta below betaup, or betaup if they are all above
    maxb = min(max(para(betamap(i),para(betamap(i),:)<paramax(betamap(i))))*(1+flact_checkpara),paramax(betamap(i)));
    if isempty(maxb) 
        maxb=paramax(betamap(i));
    end
    
    %if minb or maxb where empty and reinizialized in the lines above,
    %then max<min or min>max.
    %here I force the ensambele to shuffle at the limint + or - flact_checkpara
    if minb >= maxb
        maxb=paramax(betamap(i));
        minb=maxb*(1-flact_checkpara);
    end
    if maxb <= minb
        minb= paramin(betamap(i));
        maxb= minb*(1+flact_checkpara);
    end


    dim3 = size(para(betamap(i),para(betamap(i),:)<paramin(betamap(i))));
    para(betamap(i),para(betamap(i),:)<paramin(betamap(i)))=rand(dim3).*(maxb-minb) + minb;
   
    dim4 = size(para(betamap(i),para(betamap(i),:)>paramax(betamap(i))));
    para(betamap(i),para(betamap(i),:)>paramax(betamap(i)))=rand(dim4).*(maxb-minb) + minb;
   
end
 

%out-of-bound Z,D,mu and theta are resampled across their ranges 
for i=1:size(para,1)-length(alphamaps)-length(betamap)
    para(i,para(i,:)<paramin(i))=random('uniform', paramin(i), paramax(i), size(para(i,para(i,:)<paramin(i)))); % selecting random values between the bound for each ensamble out
    para(i,para(i,:)>paramax(i))=random('uniform', paramin(i), paramax(i), size(para(i,para(i,:)>paramax(i))));
end

