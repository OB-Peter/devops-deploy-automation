FROM python:3.11-alpine
WORKDIR /app
RUN echo '<h1>Deployed OK</h1>' > index.html
EXPOSE 3000
CMD python -m http.server 3000
