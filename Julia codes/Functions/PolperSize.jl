# For tau, this contains firms that wont default
function Ushape(binnum, SumPol, mu)

    totalmass = sum(mu)
    maxval = maximum(SumPol[:, 1] .+ SumPol[:, 3])
    bins = [10; exp.(range(log(50), log(maxval+1), binnum-1))]
    
    avg_CFL = zeros(binnum, 1)
    avg_pdef  = zeros(binnum, 1)
    mu_CFL = zeros(binnum, 1)
    
    n = size(SumPol,1)-1 
    for bin = 1:binnum

        for s_i = 1:n

            xval = SumPol[s_i, 1] + SumPol[s_i, 3]

            if bin == 1

                if  SumPol[s_i, 4] != 0 && xval < bins[bin]
                    avg_CFL[bin] += mu[s_i]/totalmass * SumPol[s_i,17]
                    avg_pdef[bin] += mu[s_i]/totalmass * SumPol[s_i,8]
                    mu_CFL[bin] += mu[s_i]/totalmass
                end  

            else

                if  SumPol[s_i, 4] != 0 && xval > bins[bin-1] && xval < bins[bin]
                    avg_CFL[bin] += mu[s_i]/totalmass * SumPol[s_i,17]
                    avg_pdef[bin] += mu[s_i]/totalmass * SumPol[s_i,8]
                    mu_CFL[bin] += mu[s_i]/totalmass
                end  

            end  
        end
    end

    avg_CFL = avg_CFL ./ mu_CFL
    avg_pdef = avg_pdef ./ mu_CFL

    plot(string.(round.(bins ./ 10)), avg_CFL, title = "Average CFL", xrotation=45, label = "avg_tau", linewidth = 3, size=(800, 600))
    plot!(string.(round.(bins ./ 10)), avg_pdef, label = "avg_pdef", linewidth = 3)

end


# For tau, this does not contain firms that wont default
function Xcross(binnum, SumPol, mu)

    totalmass = sum(mu)
    maxval = maximum(SumPol[:, 1] .+ SumPol[:, 3])
    bins = [10; exp.(range(log(50), log(maxval+1), binnum-1))]
    
    avg_tau = zeros(binnum, 1)
    avg_gam = zeros(binnum, 1)
    mu_part = zeros(binnum, 1)
    
    n = size(SumPol,1)-1 
    for bin = 1:binnum

        for s_i = 1:n

            xval = SumPol[s_i, 1] + SumPol[s_i, 3]

            if bin == 1

                if  SumPol[s_i, 4] != 0 && SumPol[s_i, 8] != 0 && xval < bins[bin]

                    avg_tau[bin] += mu[s_i]/totalmass * SumPol[s_i,17]
                    avg_gam[bin] += mu[s_i]/totalmass * SumPol[s_i,14]
                    mu_part[bin] += mu[s_i]/totalmass

                end  

            else

                if  SumPol[s_i, 4] != 0 && SumPol[s_i, 8] != 0 && xval > bins[bin-1] && xval < bins[bin]
                    
                    avg_tau[bin] += mu[s_i]/totalmass * SumPol[s_i,17]
                    avg_gam[bin] += mu[s_i]/totalmass * SumPol[s_i,14]
                    mu_part[bin] += mu[s_i]/totalmass

                end  

            end  
        end
    end

    avg_tau = avg_tau ./ mu_part
    avg_gam = avg_gam ./ mu_part


    plot(string.(round.(bins ./ 10)), avg_tau, title = "Average CFL and Liquidation Probability",
         xrotation = 45, color=:blue, label = "Avg CFL rel.", linewidth = 3, size = (800, 600), legend = :bottomleft)
    plot!(string.(round.(bins ./ 10)), avg_gam, color=:red, label = "Avg Pr. Liq.", linewidth = 3)


end


function QBplot(binnum, SumPol, SumPol0, mu, mu0)

    totalmass = sum(mu)
    maxval = maximum(SumPol[:, 1] .+ SumPol[:, 3])
    bins = [10; exp.(range(log(50), log(maxval+1), binnum-1))]
    
    avg_b = zeros(binnum, 1)
    avg_q = zeros(binnum, 1)
    mu_part = zeros(binnum, 1)
    
    n = size(SumPol,1)-1 
    for bin = 1:binnum

        for s_i = 1:n

            xval = SumPol[s_i, 1] + SumPol[s_i, 3]

            if bin == 1

                if  SumPol[s_i, 3] != 0 && xval < bins[bin]

                    avg_b[bin] += mu[s_i]/totalmass * SumPol[s_i,4]
                    avg_q[bin] += mu[s_i]/totalmass * SumPol[s_i,9]
                    mu_part[bin] += mu[s_i]/totalmass

                end  

            else

                if  SumPol[s_i, 3] != 0 && xval > bins[bin-1] && xval < bins[bin]
                    
                    avg_b[bin] += mu[s_i]/totalmass * SumPol[s_i,4]
                    avg_q[bin] += mu[s_i]/totalmass * SumPol[s_i,9]
                    mu_part[bin] += mu[s_i]/totalmass

                end  

            end  
        end
    end 

    avg_b8 = log10.(avg_b ./ mu_part)
    avg_q8 = avg_q ./ mu_part

    # same for sumpol 0
    maxval = maximum(SumPol0[:, 1] .+ SumPol0[:, 3])
    bins = [10; exp.(range(log(50), log(maxval+1), binnum-1))]
    
    avg_b = zeros(binnum, 1)
    avg_q = zeros(binnum, 1)
    mu_part = zeros(binnum, 1)
    
    n = size(SumPol0,1)-1 
    for bin = 1:binnum

        for s_i = 1:n

            xval = SumPol0[s_i, 1] + SumPol0[s_i, 3]

            if bin == 1

                if  SumPol0[s_i, 3] != 0 && xval < bins[bin]

                    avg_b[bin] += mu0[s_i]/totalmass * SumPol0[s_i,4]
                    avg_q[bin] += mu0[s_i]/totalmass * SumPol0[s_i,9]
                    mu_part[bin] += mu0[s_i]/totalmass

                end  

            else

                if  SumPol0[s_i, 3] != 0 && xval > bins[bin-1] && xval < bins[bin]
                    
                    avg_b[bin] += mu0[s_i]/totalmass * SumPol0[s_i,4]
                    avg_q[bin] += mu0[s_i]/totalmass * SumPol0[s_i,9]
                    mu_part[bin] += mu0[s_i]/totalmass

                end  

            end  
        end
    end

    avg_b0 = log10.(avg_b ./ mu_part)
    avg_q0 = avg_q ./ mu_part

    # First plot: Average Log Debt
    plota = plot(string.(round.(bins ./ 10)), avg_b8,
        title = "Average Log Debt", xrotation = 45, legend = true,
        linewidth = 3, label = "ABL + CFL", size = (600, 300), color = :blue)

    plot!(string.(round.(bins ./ 10)), avg_b0, 
        linewidth = 3, linestyle = :dash, label = "ABL only", color = :red)  # Dashed line

    # Second plot: Average Interest Rates
    plotb = plot(string.(round.(bins ./ 10)), avg_q8, 
        title = "Average Interest Rates", xrotation = 45, legend = true, 
        linewidth = 3, label = "ABL + CFL", size = (600, 300), color = :blue)

    plot!(string.(round.(bins ./ 10)), avg_q0, 
        linewidth = 3, linestyle = :dash, label = "ABL only", color = :red)  # Dashed line

    # Combine the two plots
    plot(plota, plotb)
end

