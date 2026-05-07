const { app } = require('./app');
const { env } = require('./config/env');
const { ensureMongoCollections } = require('./db/mongo');
const { ensurePostgresSchema } = require('./db/postgres');

async function bootstrap() {
  try {
    await ensurePostgresSchema();

    try {
      await ensureMongoCollections();
    } catch (error) {
      console.warn('MongoDB initialization skipped.', error.message);
    }

    app.listen(env.port, () => {
      console.log(`HanapGawa backend listening on port ${env.port}`);
    });
  } catch (error) {
    console.error('Failed to start HanapGawa backend', error);
    process.exit(1);
  }
}

bootstrap();
