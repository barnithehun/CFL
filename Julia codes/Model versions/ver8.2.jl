###########################################################################
############### VER 8.2 - Optimal liquidation decision  ##################
###########################################################################

using LinearAlgebra, Statistics, LaTeXStrings, Plots, QuantEcon, Roots, NamedArrays, SparseArrays, Dates, XLSX, DataFrames, Distributions, Random

################ Importing Result and Diagnostic Functions ###################
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/dynsim.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/dynsim2.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/PrintPolOld.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/plotPol.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/StatDist_plot.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/sumSS.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/PolperSize.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/GamPol.jl")

################ Importing Model Functions ###################
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/FCmodel/fn_Tau_Q.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/FCmodel/EntryValue.jl")
include("C:/Users/szjud/OneDrive/Asztali gép/EBCs/CFL-git/Julia codes/Functions/FCmodel/stat_dist.jl")

##################################################################
##

function gridsize()
    # grid sizes - x, k, b should be even numbers!!
    x_size::Int = 44
    e_size::Int = 13
    k_size::Int = 26
    b_size::Int = 26
    return (x_size = x_size, e_size = e_size, k_size = k_size, b_size = b_size)
end

function parameters()
    rho_e::Float64 = 0.969
    sigma_e::Float64 = 0.146
    nul_e::Int = 1
    DRS::Float64 = 0.75
    alpha::Float64 = 1/3 * DRS
    nu::Float64 = 2/3 * DRS
    pc::Float64 = 15.0
    beta::Float64 = 0.96
    delta::Float64 = 0.06
    pdef_exo::Float64 = 0.03
    discount::Float64 = beta
    phi_a::Float64 = 0.4
    tauchen_sd::Float64 = 4.0

    kappa::Float64 = 0.3           # capital recovery rate of CFL debt
    zeta_R::Float64 = 15000.0      # fixed cost of reorganization
    tau_vec::StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}} = 0:1.0:1  # vector of CFL reliances
    zeta_L::Float64 = 100.0

    return (rho_e = rho_e, sigma_e = sigma_e, nul_e = nul_e, alpha = alpha,
            nu = nu, pc = pc, beta = beta, delta = delta, pdef_exo = pdef_exo,
            discount = discount, phi_a = phi_a, tauchen_sd = tauchen_sd,
            kappa = kappa, zeta_R = zeta_R, zeta_L = zeta_L, tau_vec = tau_vec)
end

####### FIRM OPTIM #######
function FirmOptim(wage; phi_c)

    # calling parameters
    rho_e, sigma_e, nul_e, alpha, nu, pc, beta, delta, pdef_exo, discount, phi_a, tauchen_sd, kappa, zeta_R, zeta_L, tau_vec = parameters()

    # calling grid size
    x_size, e_size, k_size, b_size = gridsize()

    # setting optimization functions
        fn_L(k,e) =  (nu*e*k^alpha / wage)^(1/(1-nu))
        fn_Y(k, e) =  e*k^alpha*fn_L(k,e)^nu
        fn_Pi(k, e) = (1-nu)*fn_Y(k,e)-pc
        fn_X(k,b,e) =  fn_Pi(k, e) + (1-delta) * k - b
        fn_D(next_k, next_b, x, q) =  x - next_k + q * next_b

        fn_Gam(k,val) = Int( (phi_a*(1-delta)*k - zeta_L) >= (phi_c*val - zeta_R)) # liquidation decision b)

        function fn_Tau_Q(pdef, gam, Pi_liq, Pi_reo, next_b, tau_vec)

            # vectorized for efficiency
            q_tau = zeros(length(tau_vec))
            if next_b == 0   
                fill!(q_tau, beta)
            else
                q_tau .= (beta ./ next_b) .* ((1 .- pdef) .* next_b .+
                    pdef .* gam .* min.(next_b, ((1 .- tau_vec) .* Pi_liq .+ tau_vec .* kappa .* Pi_liq)) .+ 
                    pdef .* (1 .- gam) .* min.(next_b, ((1 .- tau_vec) .* Pi_liq .+ tau_vec .* Pi_reo)))
            end

            q, tau_index = findmax(q_tau)

            if isapprox(q, maximum(q_tau), atol=0.001) # == won't work here, there will always be a small numerical diff
                tau = (1-gam)*Pi_reo > gam*Pi_liq ? 1 : 0
            else
                tau = tau_vec[tau_index]
            end

            return q, tau
        end

    # Setting the state-space
        # productivity process
        e_chain = tauchen(e_size, rho_e, sigma_e, (1-rho_e)*nul_e, tauchen_sd)
        e_vals = exp.(e_chain.state_values) 
        # adding exogeneous default shocks
        e_ptrans = e_chain.p .* (1-pdef_exo) 
        e_ptrans[:,1] = e_ptrans[:,1] .+ pdef_exo

        # Log-grids
        k_grid = [0;exp.(range(log(10), log(10*10^5), k_size-1))]
        b_grid = [0;exp.(range(log(10), log(10*10^5), b_size-1))]  # no savings

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
        
    #################################### 
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
                    p_trans = e_ptrans[e, next_e_i] 
            
                    # find the second closest
                    if x_next < x_grid[end] && x_next > x_grid[1]
                        
                        x_far = x_next > x_grid[x_close] ? x_close + 1 : x_close - 1
                        close_weight = abs(x_next - x_grid[x_far]) / (abs(x_next - x_grid[x_close]) + abs(x_next - x_grid[x_far]))
            
                        # finding the correspoing indicies     
                        xe_close = x_close + (next_e_i-1)*x_size
                        xe_far = x_far + (next_e_i-1)*x_size
                        
                        # filling the transition matrix
                        Q[s_i, a_i, xe_close] = p_trans*close_weight
                        Q[s_i, a_i, xe_far] = p_trans*(1-close_weight)

                    else
                        xe_close = x_close + (next_e_i-1)*x_size
                        Q[s_i, a_i, xe_close] = p_trans
                    end  
                        
                else
                    # this states two things: 
                    # 1) if you are in an def state, you will be in an def state in the next period no matter the action (row of ones)
                    # 2) if you choose def or exit action, you will be in an def state in the next period no matter the state (columns of ones)
                    Q[s_i, a_i, end] = 1
                            
                end
            end
        end
    end

    # initital (!) endogeneous default probability for each state
    kbexq_old::Array{Float64, 2} = zeros(n, 4)
    kbexq_new::Array{Float64, 2} = fill(1.0, n, 4)
    SumPol::Array{Float64, 2} = zeros(n, 18)
    # q_sa::Array{Float64, 2} = fill(0.97, n, m)
    q_sa::Array{Float64, 2} = zeros(n, m)
    pdef_sa::Array{Float64, 2} = zeros(n, m)
    gam_sa::Array{Float64, 2} = zeros(n, m)
    Pi_liq_sa::Array{Float64, 2} = zeros(n, m)
    Pi_reo_sa::Array{Float64, 2} = zeros(n, m)
    tau_sa::Array{Float64, 2} = zeros(n, m)
    iter::Int = 0
    ################ 
    while !isequal(kbexq_old,kbexq_new)

        iter += 1
        if iter >= 20
            println("Error: Iteration number exceeded $iter")
            break
        end

        kbexq_old = kbexq_new
        R = fill(-Inf,  n, m);           
        for a_i in 1:m       
         # actions
         next_b = a_vals[a_i,2]
         next_k = a_vals[a_i,1]
         next_def = a_i_vals[a_i,3]
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
                    R[s_i, a_i] = -5 
                elseif next_exit == 1
                    R[s_i, a_i] = x  
                elseif def == 1      
                    R[s_i, a_i] = 0
                end
            end
        end

        ddp = QuantEcon.DiscreteDP(R, Q, discount);
        results = QuantEcon.solve(ddp, PFI)

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

            # if the firm defaults or exits these cannot be interpreted
            if def == 0 && exit == 0
                q = q_sa[s_i, pol]
                tau = tau_sa[s_i, pol]
                gam = gam_sa[s_i, pol]    
                pdef = pdef_sa[s_i, pol]
                Pi_liq = Pi_liq_sa[s_i, pol] 
                Pi_reo = Pi_reo_sa[s_i, pol] 
            else
                q = gam = Pi_liq = Pi_reo = tau = pdef = 0 
            end

            # if the firm defaults these cannot be interpreted
            d = def == 0 ? fn_D(k, b, x, q) : 0

            # value
            val = values[s_i]

            # Summarise policies
            SumPol[s_i, :] .= [x, e, k, b, next_x, exit, def, pdef, q, l, y, Pi, d, gam, Pi_liq, Pi_reo, tau, val]    
        end
        
        ###############################################################################
        # Probability of default, liquidation, PIliq and PIreo and implied q given optimal k', b' in each state
        for s_i in 1:n

            e_i = s_i_vals[s_i, 2]

            for a_i in 1:m
                # policies given (x,e)
                next_k = a_vals[a_i,1]
                next_b = a_vals[a_i,2]

                pdef = 0
                gam = 0
                Pi_reo = 0
                Pi_liq = max(0, phi_a*(1-delta)*next_k - zeta_L)

                for next_e_i in 1:e_size

                    p_trans = e_ptrans[e_i, next_e_i]
                    x_next = fn_X(next_k,next_b,e_vals[next_e_i])

                    x_close = argmin(abs.(x_next .- x_grid))   
                    xe_close = x_close + (next_e_i-1)*x_size
                    
                    next_def_close = a_i_vals[policies[xe_close], 3]
                    val_close = values[xe_close]

                    if x_next < x_grid[end] && x_next > x_grid[1]
                        
                        x_far = x_next > x_grid[x_close] ? x_close + 1 : x_close - 1
                        # finding the correspoing indicies     
                        xe_far = x_far + (next_e_i-1)*x_size

                        next_def_far = a_i_vals[policies[xe_far], 3]
                        val_far = values[xe_far]
                        
                        close_weight = abs(x_next - x_grid[x_far]) / (abs(x_next - x_grid[x_close]) + abs(x_next - x_grid[x_far]))
                        
                        # value needed only for Pi_reo and gam
                        val = close_weight*val_close + (1-close_weight)*val_far    

                        pdef += p_trans*(close_weight*next_def_close + (1-close_weight)*next_def_far)
                        gam += p_trans * fn_Gam(next_k, val) 
                        Pi_reo += p_trans * max(phi_c*val - zeta_R, 0)

                    else # close_weight = 1
                        val = val_close
                        pdef += p_trans * next_def_close                  
                        gam += p_trans * fn_Gam(next_k, val)
                        Pi_reo += p_trans * max(phi_c*val - zeta_R, 0)                        
                    end  
                
                end 

                # saving results for summary
                q, tau = fn_Tau_Q(pdef, gam, Pi_liq, Pi_reo, next_b, tau_vec)
                pdef_sa[s_i, a_i] = pdef
                q_sa[s_i,a_i] = q
                tau_sa[s_i,a_i] = tau
                gam_sa[s_i, a_i] = gam
                Pi_liq_sa[s_i, a_i] = Pi_liq
                Pi_reo_sa[s_i, a_i] = Pi_reo
            end
        end
        kbexq_new = SumPol[:, [3, 4, 7, 9]]

    end
    println("Total 'main loop' iterations: ", iter)

    ### Incumbent dynamics ### 
    # Fmat - from state n, what is the probability of ending up in state n', given optimal policy
    Fmat = zeros(n-1,n-1)
    for s_i in 1:(n-1)
               
        # policies imported from SumPol
        next_k = SumPol[s_i, 3]
        next_b = SumPol[s_i, 4]
        
        e_i = Int(floor( (s_i-1) / x_size) + 1) 
        for next_e_i in 1:e_size

            p_trans = e_ptrans[e_i, next_e_i]
            x_next = fn_X(next_k,next_b,e_vals[next_e_i])

            x_close = argmin(abs.(x_next .- x_grid))
            xe_close = x_close + (next_e_i-1)*x_size

            if x_next < x_grid[end] && x_next > x_grid[1]
                
                x_far = x_next > x_grid[x_close] ? x_close + 1 : x_close - 1
                
                close_weight = abs(x_next - x_grid[x_far]) / (abs(x_next - x_grid[x_close]) + abs(x_next - x_grid[x_far]))
    
                # finding xe_index     
                xe_far = x_far + (next_e_i-1)*x_size

                # filling Fmat
                Fmat[s_i, xe_close] += p_trans * close_weight
                Fmat[s_i, xe_far] += p_trans * (1-close_weight)                               

            else # close_weight = 1
                Fmat[s_i, xe_close] += p_trans
            end  
        end

    end
    
    # Taking defaults into account - makes Fmat nXn
    Fmat = Fmat .* (1 .- SumPol[1:end-1, 8])
    Fmat = hcat(Fmat, SumPol[1:end-1, 8])
    Fmat = vcat(Fmat,  [zeros(1,n-1) 1] )

   return ( SumPol, e_chain, transpose(Fmat) )

end

####### ENTRANTS #######
function EntryValue(SumPol, e_chain)  

    # entrant ln(e) distribution - equal to the stationary distribution of e_chain    
    e_entry  = reduce(+,stationary_distributions(e_chain))

    # entrant X distribution - x_e = 0  in every case 
    x_vals = unique(SumPol[:, 1])
    zero_index = findall(x -> x == 0.0, x_vals)
    x_entry = zeros(length(x_vals))
    x_entry[zero_index .+ 0] .= 1 # if x = 0 prob = 1 

    # (x,e) are independent, the joint of the two distribution is their product
    xe_entry = [kron(e_entry, x_entry); 0] # also the f0 vector

    # map the entry probabilities to values
    beta = parameters().beta
    Ve = transpose(xe_entry) * (SumPol[:,end])*beta

    return ( Ve, xe_entry )    

end

####### STATIONARY DISTRIBUTION ########
function stat_dist(SumPol, Fmat, f0)

    # Exiting firms + defaulting firms
    n = size(SumPol,1)
    xpol = [SumPol[1:n-1,6] + SumPol[1:n-1,7] ; 1]
    Ident = Matrix(I,n,n)

    xpol_mat = Ident - Diagonal(xpol)   # I - diag(X)
    f0 = xpol_mat*f0                    # (I - diag(X))f0
    Mmat = Fmat*xpol_mat                # M = F(I - diag(X))

    # unscaled stationary distribution
    mu_0 = inv(Ident - Mmat)*f0         # inv(I-M)*f0

    # ok, bc exit and default implies k = 0, n = 0
    Nd = transpose(SumPol[1:n,10])*mu_0
    Ns = 10000

    # This is given that labour supply is one (10000) inelastically
    m = Ns/Nd
    mu = m.*mu_0

    return ( mu, m , xpol )

end

############ Results: calculation, only abl -> 0 ############ 
wage = 1
@elapsed SumPol, e_chain, Fmat = FirmOptim(wage, phi_c = 0.8)
c_e, f0 = EntryValue(SumPol, e_chain) 
mu, m, xpol = stat_dist(SumPol, Fmat, f0)

@elapsed SumPol0, e_chain0, Fmat0 = FirmOptim(wage, phi_c = 0)
c_e0, f00 = EntryValue(SumPol0, e_chain0) 
mu0, m0, xpol0 = stat_dist(SumPol0, Fmat0, f00)

PrintPolOld(SumPol, mu)   

############ Core results Results: stationary distributions ############
println("The relative productivity of the ABL case is: ", round(c_e0 / c_e , digits=3))
println("Fixed costs :", parameters().zeta_R, "and: ", parameters().zeta_L)  

sumSS(SumPol,Fmat,f0)
# sumSS(SumPol0,Fmat0,f00)

binnum = 10
# Pdef and CFL reliance
Ushape(binnum, SumPol, mu) # in calculating tau, this contains firms with Pdef = 0
# Gamma and CFL reliance
Xcross(binnum, SumPol, mu) # in calculating tau, this does not contain firms with Pdef = 0
# Average Debt policy and Interest rate across firm sizes
QBplot(binnum, SumPol, SumPol0, mu, mu0) 

# Q - against Gam this plot works well with x_size == 44 and e_size == 27 
plot(GamPol(SumPol, 14, 22), GamPol(SumPol, 14, 23), GamPol(SumPol, 14, 25), 
     GamPol(SumPol, 27, 22), GamPol(SumPol, 30, 23), GamPol(SumPol, 33, 25), 
     layout = (2, 3), size = (1000, 800) )

############ Results: dynamics simulations ##############

# shows the average evolution of (X,K,B) and the share of esiting firms over 25 years
_, e_size, _, _ = gridsize()
# shows the average policies of firms of a given productivity across their lifecycle
dynsim2(e_size - 2, 100000)

# shows optimal policies of firms with a certain productivity, across x-sizes
plotPol(SumPol0, SumPol, e_size - 3)



############ Firm states and policies in stationary equilibrium ###########
binnum = 20
plot(plotPDF(binnum, 'k', SumPol), plotPDF(binnum, 'b', SumPol), plotPDF(binnum, 'l', SumPol),
    plotPDF(binnum, 'y', SumPol), plotPDF(binnum, 'p', SumPol), plotPDF(binnum, 'v', SumPol), layout=(2,3), size=(1200, 800))

binnum = 10  
plot(plotCDF(binnum, 'k', SumPol), plotCDF(binnum, 'b', SumPol), plotCDF(binnum, 'l', SumPol),
    plotCDF(binnum, 'y', SumPol), plotCDF(binnum, 'p', SumPol), plotCDF(binnum, 'v', SumPol), layout=(2,3), size=(1200, 800))

plotXE(SumPol, mu, e_chain)

binnum = 10
Ushape(binnum, SumPol, mu)
Xcross(binnum, SumPol, mu)
plotTauDist(SumPol)
QBplot(binnum, SumPol, SumPol0, mu, mu0)

############ Results: dynamics simulations ##############
x_size, e_size, _, _ = gridsize()
plot(dynsim(SumPol, Fmat, simn_length = 100000, e_i = e_size-2),
     dynsim(SumPol, Fmat, simn_length = 100000, e_i = e_size-1),
     dynsim(SumPol, Fmat, simn_length = 100000, e_i = e_size), layout=(4,1), size=(1000, 800))


############ Results: compariaion of policies and firm dynamics ##############
plotPol(SumPol0, SumPol, 16)
dynsim2(15, 100000, 15)
ProdDist(SumPol, mu, SumPol0, mu0)

############ General equilibrium: solving for wage ##############
function FindWage(wage; phi_c)  

    beta = parameters().beta
    SumPol, e_chain, _ = FirmOptim(wage, phi_c = phi_c)

    # entrant productivities set to be equal to the stationary distribution of e_chain    
    e_entry  = reduce(+,stationary_distributions(e_chain))

    # entrant X distribution - x_e = 0  in every case 
    x_vals = unique(SumPol[:, 1])
    zero_index = findall(x -> x == 0.0, x_vals)
    x_entry = zeros(length(x_vals))
    x_entry[zero_index .+ 0] .= 1 # if x = 0 prob = 1 

    # (x,e) are independent, the joint of the two distribution is their product
    xe_entry = [kron(e_entry, x_entry); 0] # also the f0 vector

    # map the entry probabilities to values
    Ve = transpose(xe_entry) * (SumPol[:,end])*beta

    return ( Ve )    

end

#Finding wage given entry cost, using bisection 
tolerance = 1
wage_0 = 1
@elapsed SumPol, e_chain, Fmat = FirmOptim(wage_0, phi_c = 0)
c_e, f0 = EntryValue(SumPol, e_chain) # free entry condition
sumSS(SumPol,Fmat,f0)

phi_c = 0.7
@elapsed wage_cfl = find_zero(wage -> FindWage(wage, phi_c = phi_c) - c_e, (0.99, 1.2), Bisection(), rtol=tolerance, verbose=true)
wage_cfl = 1.0763
SumPol, e_chain, Fmat = FirmOptim(wage_cfl, phi_c = phi_c)
c_e, f0 = EntryValue(SumPol, e_chain)

results_cfl = sumSS(SumPol,Fmat,f0)


# wage_cfl = 1.0055664062499996   # e_size = 15, zeta = {15000,200}
# wage_cfl = 1.0117187499999998   # e_size = 11, zeta = {15000,0}

# wage_cfl = 1.0133691406249996   # e_size = 9, zeta = {15000,200}
# wage_cfl = 1.0348437499999998   # e_size = 9, zeta = {1000,200}


