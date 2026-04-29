function [S,E,Ir,Iu]=checkbound_yesterday(S,E,Ir,Iu,C,S_yesterday,E_yesterday,Ir_yesterday,Iu_yesterday,t)
%check variable bound, when negative it assigned the value of the previous day.
num_ens=size(S,2);

if t==1
    for k=1:num_ens
        if min(S(:,k))<0
            S(S(:,k)<0,k)=    randi([5 20],size(S(S(:,k)<0,k))) /100 .*C(S(:,k)<0);
        end
        if min(E(:,k))<0
            E(E(:,k)<0,k)=    randi([0 10],size(E(E(:,k)<0,k)) )/100 .*C(E(:,k)<0);
        end
        if min(Ir(:,k))<0
            Ir(Ir(:,k)<0,k)=  randi([0 10],size(Ir(Ir(:,k)<0,k))) /100 .*C(Ir(:,k)<0);
        end
        if min(Iu(:,k))<0
            Iu(Iu(:,k)<0,k)=  randi([0 10],size(Iu(Iu(:,k)<0,k)) )/100 .*C(Iu(:,k)<0);
        end
    end
else
    for k=1:num_ens
        S(S(:,k)<0,k)=    S_yesterday(find(S(:,k)<0),k); %#ok<*FNDSB> 
        E(E(:,k)<0,k)=    E_yesterday(find(E(:,k)<0),k);
        Ir(Ir(:,k)<0,k)=  Ir_yesterday(find(Ir(:,k)<0),k); 
        Iu(Iu(:,k)<0,k)=  Iu_yesterday(find(Iu(:,k)<0),k);
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

