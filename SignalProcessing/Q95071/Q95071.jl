# StackExchange Signal Processing Q95071
# https://dsp.stackexchange.com/questions/95071
# Build the Laplacian Matrix of Edge Preserving Multiscale Image Decomposition based on Local Extrema.
# References:
#   1.  A
# Remarks:
#   1.  Use in Julia as following:
#       -   Move to folder using `cd(raw"<PathToFolder>");`.
#       -   Activate the environment using `] activate .`.
#       -   Instantiate the environment using `] instantiate`.
#   2.  Working with 4 Connectivity seems to be better than 8 Connectivity.
# TODO:
# 	1.  Use `Krylov.jl` to support larger matrices.
# Release Notes Royi Avital RoyiAvital@yahoo.com
# - 1.0.000     17/09/2024  Royi Avital
#   *   First release.

## Packages

# Internal
using LinearAlgebra;
using Printf;
using Random;
# External
using BenchmarkTools;
using ColorTypes;          #<! Required for Image Processing
using FileIO;              #<! Required for loading images
using Krylov;
using LoopVectorization;   #<! Required for Image Processing
using PlotlyJS;            #<! Use `add Kaleido_jll@v0.1` (See https://github.com/JuliaPlots/PlotlyJS.jl/issues/479)
using SparseArrays;
using StableRNGs;
using StaticKernels;       #<! Required for Image Processing


## Constants & Configuration
RNG_SEED = 1234;

juliaCodePath = joinpath(".", "..", "..", "JuliaCode");
include(joinpath(juliaCodePath, "JuliaInit.jl"));
include(joinpath(juliaCodePath, "JuliaImageProcessing.jl"));
include(joinpath(juliaCodePath, "JuliaVisualization.jl")); #<! Display Images

## Settings

figureIdx = 0;

exportFigures = true;

oRng = StableRNG(1234);

## Functions

function BuildImgGraph( mI :: Matrix{T}, hV :: Function, hW :: Function, winRadius :: N ) where {T <: AbstractFloat, N <: Integer}
    # Build a graph of LxL neighborhood using the weights function.
    # The function must return a tuple of the value and if the value is valid (To be inserted into the adjacency graph).
    # It might be useful to only calculate the distance between the neighborhood.  
    # Then one can apply per row normalization and global normalization then apply element wise weighing.

    numRows = size(mI, 1);
    numCols = size(mI, 2);
    numPx   = numRows * numCols;
    winLen  = (N(2) * winRadius) + one(N);

    # Number of edges (Ceiled estimation as on edges there are less)
    vI = ones(Int32, winLen * winLen * numPx); #<! Must be valid index
    vJ = ones(Int32, winLen * winLen * numPx); #<! Must be valid index
    vV = zeros(T, winLen * winLen * numPx); #<! Add zero value

    elmIdx   = 0;
    refPxIdx = 0;
    for jj ∈ 1:numCols, ii ∈ 1:numRows
        refPxIdx += 1;
        for nn ∈ -winRadius:winRadius, mm ∈ -winRadius:winRadius
            if (((ii + mm) > 0) && ((ii + mm) <= numRows) && ((jj + nn) > 0) && ((jj + nn) <= numCols))
                # @infiltrate ((ii == 3) && (jj == 1))
                # Pair is within neighborhood
                isValid = hV(ii, jj, mm, nn);
                if (isValid)
                    elmIdx    += 1;
                    weightVal  = hW(mI[ii, jj], mI[ii + mm, jj + nn], ii, jj, mm, nn);
                    vI[elmIdx] = refPxIdx;
                    vJ[elmIdx] = refPxIdx + (nn * numRows) + mm;
                    vV[elmIdx] = weightVal;
                end
            end
        end
    end

    mW = sparse(vI[1:elmIdx], vJ[1:elmIdx], vV[1:elmIdx], numPx, numPx);

    return mW;

end

function NormalizeRows( mW :: AbstractSparseMatrix{T} ) where {T <: Number}

    numRows = size(mW, 1);
    numCols = size(mW, 2);
    vI, vJ, vV = findnz(mW);
    vRowSum = zeros(numRows);
    numNonZero = length(vI);

    for ii ∈ 1:numNonZero
        # @infiltrate
        vRowSum[vI[ii]] += vV[ii];
    end

    for ii ∈ 1:numRows
        vRowSum[ii] = ifelse(vRowSum[ii] != zero(T), vRowSum[ii], one(T));
    end

    for ii ∈ 1:numNonZero
        vV[ii] /= vRowSum[vI[ii]];
    end

    return sparse(vI, vJ, vV, numRows, numCols);

end

function NormalizeRows!( mA :: SparseMatrixCSC{T}, vRowSum :: AbstractVector{T} ) where {T}
    
    vV = nonzeros(mA);
    vR = rowvals(mA); #<! Row index
    vRowSum .= zero(T);
    
    for jj in axes(mA, 2)
        for kk in nzrange(mA, jj)
            ii = vR[kk]; #<! Row index
            vRowSum[ii] += vV[kk];
        end
    end

    for ii ∈ 1:length(vRowSum)
        vRowSum[ii] = ifelse(vRowSum[ii] != zero(T), vRowSum[ii], one(T));
    end
    
    for jj in axes(mA, 2)
        for kk in nzrange(mA, jj)
            ii = vR[kk];
            if(vRowSum[ii] == zero(T))
                println(vRowSum[ii]);
            end
            vV[kk] /= vRowSum[ii];
        end
    end
    
    return mA;

end


## Parameters

imgUrlGray   = raw"https://i.sstatic.net/gjTJa.png";
imgUrlMarked = raw"https://i.sstatic.net/0oqlt.png";

# Problem parameters

# Validation Function
hV(ii :: N, jj :: N, mm :: N, nn :: N) where {N <: Integer} = (abs(mm) <= N(1)) && (abs(nn) <= N(1)) && ((mm != zero(N)) || (nn != zero(N))); #<! 8 Connectivity
# hV(ii :: N, jj :: N, mm :: N, nn :: N) where {N <: Integer} = (mm * nn == zero(N)) && ((mm != zero(N)) || (nn != zero(N))); #<! 4 Connectivity
# Weighing Function
hW(valI :: T, valN :: T, ii :: N, jj :: N, mm :: N, nn :: N) where {T <: AbstractFloat, N <: Integer} = abs(valI - valN); #<! Weighing function
# hW(valI :: T, valN :: T, ii :: N, jj :: N, mm :: N, nn :: N) where {T <: AbstractFloat, N <: Integer} = exp(-((valI - valN) ^ 2) / (T(2) * mV[ii, jj])); #<! Weighing function

τ         = 0.25;
ϵ         = 1e-5;
mC        = GenColorConversionMat(RGB_TO_YIQ); #<! Color conversion matrix
winRadius = 1;
β         = 200.0;

# Solver Parameters


#%% Load / Generate Data

# Gray / Original Image
mI = load(download(imgUrlGray));
mI = ConvertJuliaImgArray(mI);
mI = mI ./ 255.0;

# Marked Image
mM = load(download(imgUrlMarked));
mM = ConvertJuliaImgArray(mM);
mM = mM ./ 255.0;

numRows = size(mI, 1);
numCols = size(mI, 2);
numPx   = numRows * numCols;


## Analysis

mMYiq = ConvertColorSpace(mM, mC);
mOYiq = ConvertColorSpace(mI, mC); #<! Check if needed

# Local Variance Image
mK = Kernel{(-winRadius:winRadius, -winRadius:winRadius)}(@inline w -> var(Tuple(w)));
mV = map(mK, extend(mOYiq[:, :, 1], StaticKernels.ExtensionSymmetric()));

mB = sum(abs.(mI .- mM), dims = 3) .> τ;
vV = findall(mB[:]); #<! Indices of marks (Set \mathcal{V})

# Distance Matrix (Graph)
mW = BuildImgGraph(mOYiq[:, :, 1], hV, hW, winRadius);
# Scale DR linearly
# minVal = minimum(mW.nzval);
# maxVal = maximum(mW.nzval);
# mW.nzval .= (mW.nzval .- minVal) ./ (maxVal - minVal); 

# mW.nzval .= exp.(-β .* mW.nzval) .+ ϵ; #<! Distance -> Weights

mK = Kernel{(-winRadius:winRadius, -winRadius:winRadius)}(@inline w -> minimum(((w[-1, -1], w[-1, 0], w[-1, 1], w[0, -1], w[0, 1], w[1, -1], w[1, 0], w[1, 1]) .- w[0, 0]) .^ 2));
mGV = map(mK, extend(mOYiq[:, :, 1], StaticKernels.ExtensionSymmetric()));

vR, vC, vVals = findnz(mW);
for ii ∈ 1:length(vR)
    localVar = 0.6 * mV[vR[ii]]; #<! The row is the reference pixel index
    mgVal    = mGV[vR[ii]];
    localVar = max(localVar, -mgVal / log(0.01));
    localVar = max(localVar, 0.000002) / 2;
    vVals[ii] = exp(-(vVals[ii] * vVals[ii]) / (2 * localVar)) + ϵ - ϵ; #<! Exponent function
end
mW = sparse(vR, vC, vVals, numPx, numPx);
# mW = mW + mW';
mW = NormalizeRows(mW);


vD = vec(sum(mW, dims = 2));
mD = spdiagm(0 => vD); #<! Degree Matrix (Diagonal of the sum of each row)
mL = mD .- mW;

vU = setdiff(1:numPx, vV); #<! Rest of unlabeled pixels (Set \mathcal{U})

# Permutation of **Rows and Columns** of SPD matrix will yield SPD matrix (https://math.stackexchange.com/questions/3559710)
mLᵤ = mL[vU, vU]; #<! The Laplacian sub matrix to optimize by
mR  = mL[vU, vV];
# oFLᵤ = cholesky(mLᵤ); #<! Symbolic factorization, supports in place (https://discourse.julialang.org/t/6091).

# Solving (Per channel): Lᵤ xᵤ = −R d
for ii ∈ 1:2
    mChn = view(mMYiq, :, :, ii + 1);
    vXᵥ  = mChn[vV]; #<! Anchor values
    # vXᵤ = -(oFLᵤ \ (mR * vXᵥ));
    vXᵤ = -(mLᵤ \ (mR * vXᵥ));
    mChn = view(mOYiq, :, :, ii + 1);
    mChn[vV] = vXᵥ;
    mChn[vU] = vXᵤ;
end

mO = ConvertColorSpace(mOYiq, inv(mC));


## Display Results

figureIdx += 1;

hP = DisplayImage(mI; titleStr = "Input Image");
display(hP);

if (exportFigures)
    figFileNme = @sprintf("Figure%04d.png", figureIdx);
    savefig(hP, figFileNme);
end

figureIdx += 1;

hP = DisplayImage(mM; titleStr = "Marker Image");
display(hP);

if (exportFigures)
    figFileNme = @sprintf("Figure%04d.png", figureIdx);
    savefig(hP, figFileNme);
end

figureIdx += 1;

hP = DisplayImage(mO; titleStr = "Output Image");
display(hP);

if (exportFigures)
    figFileNme = @sprintf("Figure%04d.png", figureIdx);
    savefig(hP, figFileNme);
end

figureIdx += 1;

hP = PlotSparseMat(mW); #<! Too large to display

if (exportFigures)
    figFileNme = @sprintf("Figure%04d.png", figureIdx);
    savefig(hP, figFileNme);
end

# if (exportFigures)
#     figFileNme = @sprintf("Figure%04d.html", figureIdx);
#     savefig(hP, figFileNme);
# end

