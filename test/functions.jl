using BeliefPropagation.DeepBinary: GH, G, H, GHnaive
for x=-30:1.:100
    @test_approx_eq_eps(log(GH(x)), log(G(big(x))/H(big(x))), 1e-8)
end

for x=-34:1.:34
    # println("x=$x")
    # @test_approx_eq_eps(log(GH(1,x)), log(G(big(x))/H(big(x))), 1e-8)
    @test_approx_eq_eps(log(GH(Inf,x)), log(G(big(x))/H(big(x))), 1e-8)
    @test_approx_eq_eps(log(-GH(-Inf,x)), log(G(big(-x))/H(big(-x))), 1e-8)
end


# for p in union(-1:0.001:-0.99,-0.99:0.01:0.99,0.99:0.001:1)
for uσ in 0:2.:80
    for x=-34:2.:34
        # println("uσ=$uσ x=$x")
        # @test_approx_eq_eps(log(GH(p, x)), log(GH(big(p), big(x))), 1e0)
        @test_approx_eq_eps(log(GH(uσ, x)), log(GHnaive(big(uσ), big(x))), 1e0)
    end
end

for uσ in 0:-2.:-80
    for x=-34:2.:34
        # println("uσ=$uσ x=$x")
        # @test_approx_eq_eps(log(GH(p, x)), log(GH(big(p), big(x))), 1e0)
        @test_approx_eq_eps(log(-GH(uσ, x)), log(-GHnaive(big(uσ), big(x))), 1e0)
    end
end
