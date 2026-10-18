# Compile with the full JDK ...
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /src
COPY Hello.java .
RUN javac Hello.java

# ... and run on the smaller JRE image.
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /src/Hello.class .
EXPOSE 8080
CMD ["java", "Hello"]
