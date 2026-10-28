import { drizzle } from "drizzle-orm/mysql2";
import { config } from "../config";

export const db = drizzle(config.databaseUrl);
