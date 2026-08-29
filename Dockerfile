# Scratch Dockerfile to browse the pre-migration .NET site as-is.
# Not part of any branch's history -- lives only in this throwaway worktree.
FROM mcr.microsoft.com/dotnet/sdk:10.0

WORKDIR /src
COPY GlobalCombat.Core/ ./GlobalCombat.Core/
COPY Web/ ./Web/

WORKDIR /src/Web
RUN dotnet restore
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ENV ASPNETCORE_URLS=http://0.0.0.0:8080
ENV ASPNETCORE_ENVIRONMENT=Development

EXPOSE 8080
CMD ["dotnet", "run", "--no-launch-profile"]
