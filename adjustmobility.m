function [S,E,Ir,Iu]=adjustmobility(S,E,Ir,Iu,nl,part,MI_inter_relative,t)
%adjust subpopulation size using mobility data
num_loc=size(MI_inter_relative,1);
for l=1:num_loc
    for j=part(l)+1:part(l+1)-1
        if t<=size(MI_inter_relative,2)
            S(part(l))=S(part(l))+(S(j)-round(MI_inter_relative(nl(j),t)*S(j)));
            S(j)=round((MI_inter_relative(nl(j),t)*S(j)));
          
            E(part(l))=E(part(l))+(E(j)-round(MI_inter_relative(nl(j),t)*E(j)));
            E(j)=round((MI_inter_relative(nl(j),t)*E(j)));

            Ir(part(l))=Ir(part(l))+(Ir(j)-round(MI_inter_relative(nl(j),t)*Ir(j)));
            Ir(j)=round((MI_inter_relative(nl(j),t)*Ir(j)));            

            Iu(part(l))=Iu(part(l))+(Iu(j)-round(MI_inter_relative(nl(j),t)*Iu(j)));
            Iu(j)=round((MI_inter_relative(nl(j),t)*Iu(j)));            
        end
    end
end