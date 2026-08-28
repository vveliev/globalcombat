# dotnet is not installed on the dev machine this spike targets, so the .NET side
# runs from the official SDK image rather than a local install.
FROM mcr.microsoft.com/dotnet/sdk:10.0

WORKDIR /src
COPY GlobalCombat.Core/ ./GlobalCombat.Core/
COPY GlobalCombat.GrpcHost/ ./GlobalCombat.GrpcHost/

WORKDIR /src/GlobalCombat.GrpcHost
RUN dotnet restore
# ICU isn't in this base image's minimal locale set; invariant globalization avoids pulling it in.
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

EXPOSE 5251
CMD ["dotnet", "run", "--no-launch-profile", "--urls", ""]
