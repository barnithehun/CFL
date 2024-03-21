########################################################################
###################### VER 5.3 -  CALIBRATION ##########################
########################################################################

using LinearAlgebra, Statistics, LaTeXStrings, Plots, QuantEcon, Roots, NamedArrays
using SparseArrays, Dates, XLSX, DataFrames, Distributions


pvec = 0:0.1:1;
results = zeros(16,length(pvec));

@elapsed for (iter, PVAL) in enumerate(pvec)

 println("Iteration: $iter, Value: $PVAL")


function gridsize()
    # grids sizes - x,k,b should be even numbers!!
    return(
        x_size = 40,
        e_size = 7,
        k_size = 30,
        b_size = 30)
end

function parameters()
    rho_e = 0.969
    sigma_e = 0.146
    nul_e = 1
    DRS = 0.75   
    alpha = 1/3 * DRS
    nu = 2/3 * DRS
    pc = 15
    beta = 0.97
    delta = 0.02
    pdef_exo = 0.02
    discount = beta * (1 - pdef_exo)
    phi_a = 0.5
    tauchen_sd = 4
    
    return (rho_e = rho_e, sigma_e = sigma_e, nul_e = nul_e, alpha = alpha,
            nu = nu, pc = pc, beta = beta, delta = delta, pdef_exo = pdef_exo,
            discount = discount, phi_a = phi_a, tauchen_sd = tauchen_sd)

end

####### FIRM OPTIM #######
function FirmOptim(wage)

    # calling parameters
    rho_e, sigma_e, nul_e, alpha, nu, pc, beta, delta, pdef_exo, discount, phi_a, tauchen_sd = parameters()

    # calling grid size
    x_size, e_size, k_size, b_size = gridsize()

    # setting optimization functions
        fn_L(k,e) =  (nu*e*k^alpha / wage)^(1/(1-nu))
        fn_Y(k, e) =  e*k^alpha*fn_L(k,e)^nu
        fn_Pi(k, e) = (1-nu)*fn_Y(k,e)-pc
        fn_X(k,b,e) =  fn_Pi(k, e) + (1-delta) * k - b
        fn_Q(next_k, next_b, pdef) = (next_b == 0) ? 0.97 : (beta * ((1-pdef) * next_b + pdef * min(next_b, phi_a * (1-delta) * next_k))) / next_b
        fn_D(next_k, next_b, x, q) =  x - next_k + q * next_b


    # Setting the state-space
        # productivity process
        e_chain = tauchen(e_size, rho_e, sigma_e, (1-rho_e)*nul_e, tauchen_sd)
        e_vals = exp.(e_chain.state_values)
        
        # Log-grids
        k_grid = [0;exp.(range(log(10), log(5*10^5), k_size-1))]
        b_grid = [0;exp.(range(log(10), log(5*10^5), b_size-1))]  # no savings

        x_low = fn_X(k_grid[1],b_grid[end], e_vals[1])
        x_high = fn_X(k_grid[end], b_grid[1], e_vals[end])
        x_grid_low = sort(-exp.(range(log(10), log(-x_low), ceil(div(x_size, 3))))[2:end], rev = false) # set the negative part of the x-grid size to 1/3rd
        x_grid_high = exp.(range(log(10), log(x_high), (x_size - length(x_grid_low)-1))) 
        x_grid = [ x_grid_low; 0; x_grid_high ]


        # Define Q(n,m,n) matrix
        n = x_size * e_size  # all possible states
        m = k_size * b_size  # all possible actions

        # total number of possible states, +1 state for being quit 
        s_vals = [gridmake(x_grid, e_vals) zeros(n)]           
        s_vals = [s_vals; [0 0 1]]

        s_i_vals = [gridmake(1:x_size, 1:e_size) zeros(n)] 
        s_i_vals = Int.([s_i_vals; [div(x_size,2) 1 1]])  # productivity after default does not matter

        a_vals = [gridmake(k_grid, b_grid) zeros(m,2) ]
        a_vals = [a_vals; [0 0 1 0]; [0 0 0 1]]

        a_i_vals = [gridmake(1:k_size, 1:b_size) zeros(m,2)]
        a_i_vals = Int.([a_i_vals; [1 div(b_size,2) 1 0]; [1 div(b_size,2) 0 1]])

        # adjusting the gridsize
        n = n+1
        m = m+2
        
    #################################### Standard approach
    Q = zeros(n, m, n); 
    for a_i in 1:m
        for  s_i in 1:n 

            # productivities (indicies)
            e = s_i_vals[s_i, 2]  # enough to save e, current x does not matter, since there are no financial frictions

            # actions (values)
            next_def = a_vals[a_i, 3] 
            next_exit = a_vals[a_i, 4] 
            def = s_vals[s_i,3]
            b = a_vals[a_i, 2]   
            k = a_vals[a_i, 1]   
                    
            for next_e_i in 1:e_size  
                if  def == 0 && next_def == 0 && next_exit == 0
                
                    # next period cash on hand x'(b',k',e')
                    x_next = fn_X(k,b,e_vals[next_e_i])
                    # where x falls on the grid - closer
                    x_close = argmin(abs.(x_next .- x_grid))
            
                    # probability of transition from e_i to next_e_j 
                    p_trans = e_chain.p[e, next_e_i] 
            
                    # find the second closest
                    if x_next < x_grid[end] && x_next > x_grid[1]
                        
                        if x_next > x_grid[x_close]
                            x_far = x_close + 1
                            else
                            x_far = x_close - 1
                        end
                        
                        x_close_weight = abs(x_next - x_grid[x_far]) / (abs(x_next - x_grid[x_close]) + abs(x_next - x_grid[x_far]))
            
                        # finding the correspoing indicies     
                        xe_close = x_close + (next_e_i-1)*x_size
                        xe_far = x_far + (next_e_i-1)*x_size
                        
                        # filling the transition matrix
                        Q[s_i, a_i, xe_close] = p_trans*x_close_weight
                        Q[s_i, a_i, xe_far] = p_trans*(1-x_close_weight)

                    else
                        xe_close = x_close + (next_e_i-1)*x_size
                        Q[s_i, a_i, xe_close] = p_trans
                    end  
                        
                else
                    # this states two things: 
                    # 1) if you are in an def state, you will be in an def state in the next period no matter the action
                    # 2) if you choose and def action, you will be in an def state in the next period no matter the state
                    Q[s_i, a_i, end] = 1
                            
                end
            end
        end
    end

    # initital (!) endogeneous default probability for each state
    q_sa = fill(0.97,n,m)
    pdef_sa = zeros(n,m);
    kbexq_old = zeros(n,4)
    kbexq_new = fill(1,n,4)
    SumPol = zeros(n, 14)
    policies = zeros(n,1)
    ################ 
    while !isequal(kbexq_old,kbexq_new)

        kbexq_old = kbexq_new
        
        R = fill(-Inf,  n, m);
        for a_i in 1:m           
                # actions
                next_b = a_vals[a_i,2]
                next_k = a_vals[a_i,1]
                next_def =  a_i_vals[a_i,3]
                next_exit =  a_i_vals[a_i,4]

                for s_i in 1:n
                    
                    def = s_vals[s_i, 3]
                    x = s_vals[s_i, 1]

                    if next_def == 0 && def == 0 && next_exit == 0
                            
                        # dividends
                        q = q_sa[s_i,a_i]
                        d = fn_D(next_k, next_b, x, q)

                        if d >= 0
                            R[s_i, a_i] = d 
                        end

                    elseif next_def == 1 
                        R[s_i, a_i] = -5  # -5000 if you want anyone to quit on its own
                    elseif next_exit == 1
                        R[s_i, a_i] = x  
                    elseif def == 1      
                        R[s_i, a_i] = 0
                    end
                end
            end

            ddp = QuantEcon.DiscreteDP(R, Q, discount);
            results = QuantEcon.solve(ddp, PFI)

            # interpreting results
            values = results.v;
            policies = results.sigma;  # optimal policy     

            ###################################################################
            # summarising results
            for s_i in 1:n

                # states
                x = s_vals[s_i, 1]
                e = s_vals[s_i, 2]

                # policies
                pol = policies[s_i]
                k = a_vals[pol,1]
                b = a_vals[pol,2]
                def = a_vals[pol,3]
                exit = a_vals[pol,4]

                # cash on hand if productivity stays the same
                next_x = fn_X(k, b, e)

                # implied firm policies
                l = fn_L(k,e)  # n is taken by gridsizefun
                y = fn_Y(k,e)
                Pi = fn_Pi(k,e)

                # Def
                if def == 0
                    pdef = pdef_sa[s_i, pol]
                    q = q_sa[s_i, pol]
                    d = fn_D(k, b, x, q)
                else
                    q = 0
                    pdef = 0
                    d = 0
                end

                # value
                val = values[s_i]

                # Summarise policies
                SumPol[s_i, :] .= [x, e, k, b, next_x, exit, def, pdef, q, l, y, Pi, d, val]    
                
            end
            
            ###############################################################################
            # Probability of default and implied q given optimal k', b' in each state
            for s_i in 1:n

                e_i = s_i_vals[s_i, 2]

                for a_i in 1:m
                    # policies given (x,e)
                    next_k = a_vals[a_i,1]
                    next_b = a_vals[a_i,2]

                    pdef_endo = 0

                    for next_e_i in 1:e_size

                        p_trans = e_chain.p[e_i, next_e_i]
                        x_next = fn_X(next_k,next_b,e_vals[next_e_i])

                        x_close = argmin(abs.(x_next .- x_grid))   
                        xe_close = x_close + (next_e_i-1)*x_size
                        next_def_close = a_i_vals[policies[xe_close], 3]

                        if x_next < x_grid[end] && x_next > x_grid[1]
                            
                            if x_next > x_grid[x_close]
                                x_far = x_close + 1
                                else
                                x_far = x_close - 1
                            end
                            
                            x_close_weight = abs(x_next - x_grid[x_far]) / (abs(x_next - x_grid[x_close]) + abs(x_next - x_grid[x_far]))
                
                            # finding the correspoing indicies     
                            xe_far = x_far + (next_e_i-1)*x_size

                            # default policy given (x,e)
                            next_def_far = a_i_vals[policies[xe_far], 3]
                            
                            # update endogeneous default probability
                            pdef_endo += p_trans*(x_close_weight*next_def_close + (1-x_close_weight)*next_def_far)

                        else # x_close_weight = 1
                            pdef_endo += p_trans * next_def_close
                        end  
                    
                    end 

                    # saving results for summary
                    pdef = 1 - ((1 - pdef_exo) * (1 - pdef_endo))
                    pdef_sa[s_i, a_i] = pdef
                    q_sa[s_i,a_i] = fn_Q(next_k, next_b, pdef)

                end
            end

        kbexq_new = SumPol[:, [3, 4, 7, 9]]

    end

    ### Incumbent and exit dynamics ### 
    # Fmat - from state n, what is the probability of ending up instate n', given optimal policy
    Fmat = zeros(n-1,n-1)
    for s_i in 1:(n-1)
               
        # policies imported from SumPol
        next_k = SumPol[s_i, 3]
        next_b = SumPol[s_i, 4]
        
        
        e_i = Int(floor( (s_i-1) / x_size) + 1)    # x_i = s_i % x_size
        for next_e_i in 1:e_size

            p_trans = e_chain.p[e_i, next_e_i]
            x_next = fn_X(next_k,next_b,e_vals[next_e_i])

            x_close = argmin(abs.(x_next .- x_grid))   
            xe_close = x_close + (next_e_i-1)*x_size

            if x_next < x_grid[end] && x_next > x_grid[1]
                
                if x_next > x_grid[x_close]
                    x_far = x_close + 1
                    else
                    x_far = x_close - 1
                end
                
                x_close_weight = abs(x_next - x_grid[x_far]) / (abs(x_next - x_grid[x_close]) + abs(x_next - x_grid[x_far]))
    
                # finding xe_index     
                xe_far = x_far + (next_e_i-1)*x_size

                # filling Fmat
                Fmat[s_i, xe_close] += p_trans * x_close_weight
                Fmat[s_i, xe_far] += p_trans * (1-x_close_weight)                               

            else # x_close_weight = 1
                Fmat[s_i, xe_close] += p_trans
            end  
        
        end 
        
    end

    return ( SumPol, e_chain, transpose(Fmat) )

end


####### ENTRANTS #######

# mapping the productivity process
function EntryValue(SumPol,
                     e_chain,
                     beta = 0.97)  

    # entrant ln(e) distribution
    # here, set to be equal to the stationary distribution of e_chain
    e_entry  = reduce(+,stationary_distributions(e_chain))

    # entrant X distribution - x_e = 0  in every case 
    x_vals = unique(SumPol[:, 1])
    x_entry = zeros(length(x_vals))
    x_entry[Int(length(x_vals)/2)] = 1 # if x = 0 prob = 1 

    #= alternative: x_e is a lognormal distribution
        x_dist = 200*LogNormal(0.4,0.4)-300
        x_entry = zeros(length(x_vals))
        for i = eachindex(x_vals)
            if i == 1
                x_entry[i] = cdf(x_dist, x_vals[i])
            else
                x_entry[i] = cdf(x_dist, x_vals[i]) - cdf(x_dist, x_vals[i-1])
            end
        end
    =# 

    # (x,e) are independent, the joint of the two distribution is their product
    xe_entry = kron(e_entry, x_entry) # also the f0 vector

    # map the entry probabilities to values
    Ve = transpose(xe_entry) * (SumPol[1:(end-1),end])*beta

    return ( Ve, xe_entry )    

end

#= Finding wage given entry cost, using bisection 
   tolerance = 1e-1
   c_e = 1000
   @elapsed result = find_zero(wage -> EntryValue(SumPol, e_chain, wage) - c_e, (0.5, 5), Bisection(), rtol=tolerance, verbose=true)
   @elapsed SumPol, e_chain, Fmat = FirmOptim(wage)
   wage = result0
=#

#Finding the the entry cost consistent with wage = 1
wage = 2
@elapsed SumPol, e_chain, Fmat = FirmOptim(wage)
c_e, f0 = EntryValue(SumPol, e_chain) # free entry condition

####### STATIONARY DISTRIBUTION ########
function stat_dist(SumPol, Fmat, f0)
    pdef_exo = parameters().pdef_exo   

    # Exiting firms (voluntary + involuntary)
    n = size(SumPol,1)-1
    xpol = SumPol[1:n,6] + SumPol[1:n,7]
    xpol = [x == 0 ? pdef_exo : x for x in xpol]  # exogeneous default shocks
    Ident = Matrix(I,n,n)

    xpol_mat = Ident - Diagonal(xpol)   # I - diag(X)
    f0 = xpol_mat*f0                    # (I - diag(X))f0 - entrants may quit immidiately
    Mmat = Fmat*xpol_mat                # M = F(I - diag(X))

    # unscaled stationary distribution
    mu_0 = inv(Ident - Mmat)*f0         # inv(I-M)*f0

    # ok, bc exit and default implies k = 0, n = 0
    Nd = transpose(SumPol[1:n,10])*mu_0

    # This is given that labour supply is one (10000) inelastically
    m = 10000/Nd
    mu = m.*mu_0

    return ( mu, m , xpol)
        
end

########## RESULTS ###########
x_size, e_size, _, _ = gridsize()
mu, m, xpol = stat_dist(SumPol, Fmat, f0)
n = size(SumPol,1)-1

totalmass = sum(mu)
exitmass=transpose(mu)*xpol 
entrymass = m*(1-transpose(xpol)*f0)  # m, needs to be adjusted with the firms that decide to quit immidiately
exitshare = exitmass/totalmass

totK = transpose(mu)*SumPol[1:n,3]
totB = transpose(mu)*SumPol[1:n,4]
totL = transpose(mu)*SumPol[1:n,10] # Ns = Nd
totY = transpose(mu)*SumPol[1:n,11]
totPi = transpose(mu)*SumPol[1:n,12]

YtoL = totY/totL

meanL = totL / totalmass 
meanK = totK / totalmass 
meanY = totY / totalmass 

# here LIE does not work bc. Im averaging ratios
avg_b2k = transpose(mu) * ifelse.(isnan.(SumPol[1:n,4] ./ SumPol[1:n, 3]) .| isinf.(SumPol[1:n,4] ./ SumPol[1:n, 3]), 0, SumPol[1:n,4] ./ SumPol[1:n, 3]) / totalmass
# average interest rate
avg_rate = 1/((transpose(mu) *SumPol[1:n,9])/totalmass)-1
# average productivity of active firms
avg_prod = transpose(mu) * ifelse.(isnan.(SumPol[1:n,11] ./ SumPol[1:n, 10]) .| isinf.(SumPol[1:n,11] ./ SumPol[1:n, 10]), 0, SumPol[1:n,11] ./ SumPol[1:n, 10]) / totalmass


results[:,iter] = vcat(totalmass, exitmass, entrymass, exitshare, totK, totB, totL, totY, totPi, YtoL, meanL, meanK, meanY, avg_b2k, avg_rate, avg_prod)

end

varnames = ["totalmass", "exitmass", "entrymass", "exitshare", "totK", "totB", "totL", "totY", "totPi", "YtoL", "meanL", "meanK", "meanY", "avg_b2k", "avg_rate", "avg_prod"];
results = NamedArray(results, names=( varnames, string.(pvec) ) ,  dimnames=("Res", "ParamVal"))
