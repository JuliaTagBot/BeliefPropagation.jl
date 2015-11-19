using MacroUtils
include("cnf.jl")
typealias MessU Float64  # ̂ν(a→i) = P(σ_i != J_ai)
typealias MessH Float64 #  ν(i→a) = P(σ_i != J_ai)
MessU()= MessU(0.)

typealias PU Ptr{MessU}
typealias PH Ptr{MessH}
getref(v::Vector, i::Integer) = pointer(v, i)

# typealias PU Ref{MessU}
# typealias PH Ref{MessH}
# getref(v::Vector, i::Integer) = Ref(v, i)


Base.getindex(p::Ptr) = unsafe_load(p)
Base.setindex!{T}(p::Ptr{T}, x::T) = unsafe_store!(p, x)
typealias VU Vector{MessU}
typealias VH Vector{MessH}
typealias VRU Vector{PU}
typealias VRH Vector{PH}

type Fact
    πlist::Vector{MessH}
    ηlist::VRU
end
Fact() = Fact(VH(), VRU())

type Var
    ηlistp::Vector{MessU}
    ηlistm::Vector{MessU}
    πlistp::VRH
    πlistm::VRH

    #used only in BP+reinforcement
    ηreinfp::MessU
    ηreinfm::MessU
end

Var() = Var(VU(),VU(), VRH(), VRH(), 0., 0.)

abstract FactorGraph
type FactorGraphKSAT <: FactorGraph
    N::Int
    M::Int
    fnodes::Vector{Fact}
    vnodes::Vector{Var}
    σ::Vector{Int}
    cnf::CNF
    fperm::Vector{Int}
    vperm::Vector{Int}

    function FactorGraphKSAT(cnf::CNF)
        @extract cnf M N clauses
        println("# read CNF formula")
        println("# N=$N M=$M α=$(M/N)")
        fnodes = [Fact() for i=1:M]
        vnodes = [Var() for i=1:N]
        kf = map(length, clauses)
        kvp = zeros(Int, N)
        kvm = zeros(Int, N)
        for clause in clauses
            for id in clause
                if id > 0
                    kvm[abs(id)] += 1
                else
                    kvp[abs(id)] += 1
                end
            end
        end

        ## Reserve memory in order to avoid invalidation of Refs
        for (a,f) in enumerate(fnodes)
            sizehint!(f.πlist, kf[a])
            sizehint!(f.ηlist, kf[a])
        end
        for (i,v) in enumerate(vnodes)
            sizehint!(v.ηlistm, kvm[i])
            sizehint!(v.ηlistp, kvp[i])
            sizehint!(v.πlistm, kvm[i])
            sizehint!(v.πlistp, kvp[i])
        end

        for (a, clause) in enumerate(clauses)
            for id in clause
                i = abs(id)
                assert(id != 0)
                f = fnodes[a]
                v = vnodes[i]
                if id > 0
                    push!(v.ηlistm, MessU())
                    push!(f.ηlist, getref(v.ηlistm,length(v.ηlistm)))

                    push!(f.πlist, MessH())
                    push!(v.πlistm, getref(f.πlist,length(f.πlist)))
                else
                    push!(v.ηlistp, MessU())
                    push!(f.ηlist, getref(v.ηlistp,length(v.ηlistp)))

                    push!(f.πlist, MessH())
                    push!(v.πlistp, getref(f.πlist,length(f.πlist)))
                end
            end
        end
        σ = ones(Int, N)
        fperm = collect(1:M)
        vperm = collect(1:N)
        new(N, M, fnodes, vnodes, σ, cnf, fperm, vperm)
    end
end

type ReinfParams
    reinf::Float64
    step::Float64
    wait_count::Int
    ReinfParams(reinf=0., step = 0.) = new(reinf, step, 0)
end

deg(f::Fact) = length(f.ηlist)
degp(v::Var) = length(v.ηlistp)
degm(v::Var) = length(v.ηlistm)

function initrand!(g::FactorGraphKSAT)
    for f in g.fnodes
        for k=1:deg(f)
            f.πlist[k] = rand()
        end
    end
    for v in g.vnodes
        for k=1:degp(v)
            r = 0.5*rand()
            v.ηlistp[k] = (1-2r)/(1-r)
        end
        for k=1:degm(v)
            r = 0.5*rand()
            v.ηlistm[k] = (1-2r)/(1-r)
        end
        v.ηreinfm = 0
        v.ηreinfp = 0
    end
end

# function decrease_reinforcement!(g::FactorGraphKSAT, reinfp::ReinfParams)
#     println("reinf: $(reinfp.reinf) -> $(reinfp.reinf /= 2)")
#     println("reinf_step: $(reinfp.step) -> $(reinfp.step /= 2)")
#     reinfp.wait_count = 0
#
#     for f in g.fnodes
#         for k=1:deg(f)
#             if !isfinite(f.πlist[k])
#                 f.πlist[k] = rand()
#             end
#         end
#     end
#     for v in g.vnodes
#         for k=1:degp(v)
#             if !isfinite(v.ηlistp[k])
#                 r = 0.5*rand()
#                 v.ηlistp[k] = (1-2r)/(1-r)
#             end
#         end
#         for k=1:degm(v)
#             if !isfinite(v.ηlistm[k] )
#                 r = 0.5*rand()
#                 v.ηlistm[k] = (1-2r)/(1-r)
#             end
#         end
#         v.ηreinfm = 0
#         v.ηreinfp = 0
#     end
# end

function update!(f::Fact)
    @extract f ηlist πlist
    Δ = 1.
    η = 1.
    eps = 1e-15
    nzeros = 0
    @inbounds for i=1:deg(f)
        if πlist[i] > eps
            η *= πlist[i]
        else
            # println("here")
            nzeros+=1
        end
    end
    @inbounds for i=1:deg(f)
        if nzeros == 0
            ηi = η / πlist[i]
        elseif nzeros == 1 && πlist[i] < eps
            ηi = η
        else
            ηi = 0.
        end
        # old = ηlist[i][]
        ηlist[i][] = ηi
        # Δ = max(Δ, abs(ηi  - old))
    end
    Δ
end

function update!(v::Var, reinf::Float64 = 0.)
    #TODO check del denominatore=0
    @extract v ηlistp ηlistm πlistp πlistm
    Δ = 1.
    eps = 1e-15

    ### compute total fields
    #πp, πm, nzerosp, nzerosm = πpm(v)
    πp, πm = πpm(v)

    ### compute cavity fields
    @inbounds for i=1:degp(v)
        # if nzerosp == 0
            πpi = πp / (1-ηlistp[i])
        # elseif (nzerosp == 1) && (1-ηlistp[i] < eps)
        #     πpi = πp
        # else
        #     πpi = 0.
        # end
        # old = πlistp[i][]
        πlistp[i][] = πpi  / (πpi + πm)
        # Δ = max(Δ, abs(πlistp[i][] - old))
    end

    @inbounds for i=1:degm(v)
        # if nzerosm == 0
            πmi = πm / (1-ηlistm[i])
        # elseif (nzerosm == 1) && (1-ηlistm[i] < eps)
            # πmi = πm
        # else
            # πmi = 0.
        # end
        # old = πlistm[i][]
        πlistm[i][] = πmi / (πmi + πp)
        # Δ = max(Δ, abs(πlistm[i][]  - old))
    end
    ###############

    #### update reinforcement ######
    if πp < πm
        p = πp / (πp+πm)
        #vecchio reinforcement
        # v.ηreinfp = reinf * (1 - 2p) / (1-p)

        # p = p^reinf /(p^reinf+(1-p)^reinf)
        v.ηreinfp = 1 - (p/(1-p))^reinf

        v.ηreinfm = 0
    else
        q = πm / (πp+πm)
        #vecchio reinforcement
        # v.ηreinfm = reinf * (1 - 2q) / (1-q)

        # q = q^reinf /(q^reinf+(1-q)^reinf)
        # v.ηreinfm = (1 - 2q) / (1-q)
        v.ηreinfm = 1 - (q/(1-q))^reinf

        v.ηreinfp = 0
    end
    #########################

    return Δ
end

function oneBPiter!(g::FactorGraph, reinf::Float64=0.)
    @extract g fperm vperm
    Δ = 1.

    shuffle!(fperm)
    @inbounds for a in fperm
        d = update!(g.fnodes[a])
        #Δ = max(Δ, d)
    end

    shuffle!(vperm)
    @inbounds for i in vperm
        d = update!(g.vnodes[i], reinf)
        #Δ = max(Δ, d)
    end

    return Δ
end

function update_reinforcement!(reinfpar::ReinfParams)
    if reinfpar.wait_count < 4
        reinfpar.wait_count += 1
    else
        reinfpar.reinf = 1 - (1-reinfpar.reinf) * (1-reinfpar.step)
    end
end

function getconfig(g::FactorGraph)
    return Int[1-2signbit(mag(v)) for v in g.vnodes]
end

function getconfig!(g::FactorGraph)
    @extract g N vnodes σ
    @inbounds for i = 1:N
        σ[i] = 1 - 2signbit(mag(vnodes[i]))
    end
    return σ
end

function converge!(g::FactorGraph; maxiters::Int = 100, ϵ::Float64=1e-5, reinfpar::ReinfParams=ReinfParams())
    for it=1:maxiters
        write("it=$it ... ")
        Δ = oneBPiter!(g, reinfpar.reinf)
        σ = getconfig!(g)
        E = energy(g.cnf, σ)
        @printf("reinf=%.3f E=%d  Δ=%f \n",reinfpar.reinf, E, Δ)
        update_reinforcement!(reinfpar)
        if E == 0
            println("Found Solution!")
            break
        end
        if Δ < ϵ
            println("Converged!")
            break
        end
    end
end

function energy(cnf::CNF, σ)
    @extract cnf M clauses
    E = M
    @inbounds for c in clauses
        for i in c
            if sign(i) == σ[abs(i)]
                E -= 1
                break
            end
        end
    end
    return E
end

@inline function πpm(v::Var)
    @extract v ηlistp ηlistm ηreinfp ηreinfm
    eps = 1e-15
    nzp = 0
    nzm = 0
    πp = 1.

    @inbounds for j in 1:length(ηlistp)
    # if 1 - ηlistp[j] > eps
        πp *= 1 - ηlistp[j]
    # else
    #     # println("there")
    #     nzp += 1
    # end
    end
    πm = 1.
    @inbounds for j in 1:length(ηlistm)
    # if 1 - ηlistm[j] > eps
        πm *= 1 - ηlistm[j]
    # else
    #     nzm += 1
    # end
    end
    #(nzp > 0 && nzm > 0) && exit("contradiction")
    πp *= 1 - ηreinfp
    πm *= 1 - ηreinfm

    return πp, πm #, nzp, nzm
end

@inline function mag(v::Var)
    #πp, πm, _, _ = πpm(v)
    πp, πm = πpm(v)
    # pup = P(σ_i = 1)
    return (πp - πm) / (πm + πp)
end

#mags(g::FactorGraph) = Float64[mag(v) for v in g.vnodes]

function solveKSAT(cnfname::AbstractString; kw...)
    cnf = readcnf(cnfname)
    solveKSAT(cnf; kw...)
end

function solveKSAT(; N::Int=1000, α::Float64=3., k::Int = 4, seed_cnf::Int=-1, kw...)
    if seed_cnf > 0
        srand(seed_cnf)
    end
    cnf = CNF(N, k, α)
    solveKSAT(cnf; kw...)
end

function solveKSAT(cnf::CNF; maxiters::Int = 10000, ϵ::Float64 = 1e-6,
                reinf::Float64 = 0., reinf_step::Float64= 0.01,
                seed::Int = -1)
    if seed > 0
        srand(seed)
    end
    reinfpar = ReinfParams(reinf, reinf_step)
    g = FactorGraphKSAT(cnf)
    initrand!(g)
    converge!(g, maxiters=maxiters, ϵ=ϵ, reinfpar=reinfpar)
    return getconfig(g)
end