function [S,E,Ir,Iu]=checkbound(S,E,Ir,Iu,C)
%check variable bound
%%%%% reprobe when state variable goes negative
num_ens=size(S,2);


for k=1:num_ens

    if min(S(:,k))<0
        S(S(:,k)<0,k)=    randi([5 50],size(S(S(:,k)<0,k))) /100 .*C(S(:,k)<0);
    end
    if min(E(:,k))<0
        E(E(:,k)<0,k)=    randi([0 20],size(E(E(:,k)<0,k)) )/100 .*C(E(:,k)<0);
    end
    if min(Ir(:,k))<0
        Ir(Ir(:,k)<0,k)=  randi([0 20],size(Ir(Ir(:,k)<0,k))) /100 .*C(Ir(:,k)<0);
    end
    if min(Iu(:,k))<0
        Iu(Iu(:,k)<0,k)=  randi([0 20],size(Iu(Iu(:,k)<0,k)) )/100 .*C(Iu(:,k)<0);
    end
    
end



%% check mass balanace
num_ens=size(S,2);

pop_fraction=(S+E+Ir+Iu)./repmat(C,1,num_ens);
pop_multiplier=max(pop_fraction,1);
if  max(abs(pop_multiplier(:)-1))>.001 %is the worst violation more than 0.1%?
    S=S./pop_multiplier;
    E=E./pop_multiplier;
    Ir=Ir./pop_multiplier;
    Iu=Iu./pop_multiplier;
end
