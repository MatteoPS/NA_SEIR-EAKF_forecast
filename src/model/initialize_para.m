function [para]=initialize_para(num_loc,num_ens,parafit,alphamaps,betamap)

%all glob vars - 2 local vars in parafit + num_loc alpha + num_loc beta
size_para=size(parafit,1) - 2 + num_loc + num_loc;

%Z,D,mu,theta,alpha1,alpha2,...,alphanum_loc,beta1,...,betanum_loc
para=zeros(size_para,num_ens);


%Z     
para(1,:)=datasample(parafit(1,:),num_ens);
%D
para(2,:)=datasample(parafit(2,:),num_ens);
%mu;
para(3,:)=datasample(parafit(3,:),num_ens);
%theta
para(4,:)=datasample(parafit(4,:),num_ens);

for l=1:num_loc
    %alpha can be re inialized as country specific in the model script 
    para(alphamaps(l),:)=parafit(5,ceil(rand(1,num_ens)*size(parafit,2)));
    para(betamap(l),:)=parafit(6,ceil(rand(1,num_ens)*size(parafit,2))); %sampling from datafit
end