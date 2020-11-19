FROM mcr.microsoft.com/dotnet/core/sdk:3.1-buster AS dependencies
WORKDIR /middleware
COPY ./*.sln ./
COPY */*.csproj ./

# Restore Stage
RUN for file in $(ls *.csproj); do mkdir -p ${file%.*}/ && mv $file ${file%.*}/; done
RUN mkdir /middleware/packages/
RUN dotnet restore --packages=/middleware/packages
COPY . ./

#Build Stage
FROM mcr.microsoft.com/dotnet/core/sdk:3.1-buster AS builder

#Install sonarscanner
RUN apt update
RUN apt install -y openjdk-11-jre
RUN dotnet tool install --tool-path /bin/dotnet dotnet-sonarscanner --version 4.8.0
ENV PATH=$PATH:/bin/dotnet


ARG VersionSuffix
WORKDIR /middleware

COPY --from=dependencies /middleware/ ./

# Prepare sonarqube
#COPY st*qube.sh ./
#ARG bamboo_repository_branch_name=$bamboo_repository_branch_name
#ARG bamboo_DISABLE_SONARBRANCHES=$bamboo_DISABLE_SONARBRANCHES

RUN ./start_sonarqube.sh

RUN dotnet build --source=/middleware/packages /p:VersionSuffix=$VersionSuffix -c Release --no-restore

# Process SQ results
RUN ./stop_sonarqube.sh

#Packer
FROM mcr.microsoft.com/dotnet/core/sdk:3.1-buster AS packer
ARG VersionSuffix
WORKDIR /middleware
COPY --from=builder /middleware/ ./
RUN mkdir /BuildOutput
RUN dotnet pack --version-suffix=$VersionSuffix -c Release --no-restore --no-build -o /BuildOutput

#Tests
FROM mcr.microsoft.com/dotnet/core/sdk:3.1-buster AS tester
WORKDIR /middleware
COPY --from=packer /middleware/ ./
COPY --from=packer /BuildOutput/ /BuildOutput/
RUN mkdir /TestResults
CMD sh -c 'dotnet test -c Release --no-restore --no-build --logger trx --results-directory /TestResults; \
    cp /BuildOutput/* /artifacts; cp /TestResults/* /artifacts; exit 0'

# Publisher to push nuget packages
FROM builder as publisher

# Copy test results and nuget packages to the artifacts folder
COPY --from=packer /BuildOutput/* /artifacts/

# /artifacts is intended to bind-mounted to an external location outside of the container.
# when this image is executed, the test results will be copied to this folder,
# effectively copying them from the container to the host file system, if a mount is specified.
WORKDIR /app
#ENV ARTIFACTORY_SERVER http://tu-server-slv01.corp.waters.com:8081/artifactory/api/nuget/UNIFI-framework-s-nuget/

COPY publish_nuget.sh /app/publish_nuget.sh

#CMD ./publish_nuget.sh  ${ARTIFACTORY_SERVER}
