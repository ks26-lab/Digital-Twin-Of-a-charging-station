function soh = soh_estimator(capacity_Ah, nominal_capacity_Ah)
%SOH_ESTIMATOR Capacity ratio, bounded to [0,1].
soh = min(max(capacity_Ah/nominal_capacity_Ah,0),1);
end
