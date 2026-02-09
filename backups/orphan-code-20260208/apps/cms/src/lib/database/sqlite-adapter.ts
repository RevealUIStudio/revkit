/**
 * Optimized SQLite Database Adapter for RevealUI Content Engine
 * With query optimization and performance monitoring
 */

import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import type { DatabaseAdapter } from '@revealui/content';

export interface SqliteAdapterConfig {
  url: string;
  idType?: 'uuid' | 'number';
  enableQueryLogging?: boolean;
  connectionPool?: {
    min: number;
    max: number;
  };
}

class QueryBuilder {
  private table: string;
  private selectClause: string;
  private whereClause: string = '';
  private orderByClause: string = '';
  private limitClause: string = '';
  private offsetClause: string = '';
  private params: any[] = [];
  private countParams: any[] = [];

  constructor(table: string, selectClause: string = '*') {
    this.table = table;
    this.selectClause = selectClause;
  }

  where(conditions: any): this {
    if (!conditions) return this;

    const whereParts: string[] = [];
    this.buildWhereConditions(conditions, whereParts);

    if (whereParts.length > 0) {
      this.whereClause = `WHERE ${whereParts.join(' AND ')}`;
    }

    return this;
  }

  private buildWhereConditions(conditions: any, parts: string[], prefix: string = ''): void {
    Object.entries(conditions).forEach(([key, value]) => {
      const columnName = prefix ? `${prefix}.${key}` : key;

      if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
        // Nested conditions
        Object.entries(value).forEach(([operator, val]) => {
          parts.push(this.buildCondition(columnName, operator, val));
        });
      } else {
        // Direct equality
        parts.push(`${columnName} = ?`);
        this.params.push(value);
        this.countParams.push(value);
      }
    });
  }

  private buildCondition(column: string, operator: string, value: any): string {
    switch (operator) {
      case 'equals':
      case 'eq':
        this.params.push(value);
        this.countParams.push(value);
        return `${column} = ?`;
      case 'not_equals':
      case 'ne':
        this.params.push(value);
        this.countParams.push(value);
        return `${column} != ?`;
      case 'greater_than':
      case 'gt':
        this.params.push(value);
        this.countParams.push(value);
        return `${column} > ?`;
      case 'greater_than_or_equal':
      case 'gte':
        this.params.push(value);
        this.countParams.push(value);
        return `${column} >= ?`;
      case 'less_than':
      case 'lt':
        this.params.push(value);
        this.countParams.push(value);
        return `${column} < ?`;
      case 'less_than_or_equal':
      case 'lte':
        this.params.push(value);
        this.countParams.push(value);
        return `${column} <= ?`;
      case 'like':
        this.params.push(`%${value}%`);
        this.countParams.push(`%${value}%`);
        return `${column} LIKE ?`;
      case 'in':
        const placeholders = Array.isArray(value) ? value.map(() => '?').join(',') : '?';
        this.params.push(...(Array.isArray(value) ? value : [value]));
        this.countParams.push(...(Array.isArray(value) ? value : [value]));
        return `${column} IN (${placeholders})`;
      case 'contains':
        this.params.push(`%${value}%`);
        this.countParams.push(`%${value}%`);
        return `${column} LIKE ?`;
      default:
        // Fallback to equality
        this.params.push(value);
        this.countParams.push(value);
        return `${column} = ?`;
    }
  }

  orderBy(sort: string): this {
    if (sort) {
      // Parse sort string like "field:asc,other:desc"
      const sortParts = sort.split(',').map(s => s.trim());
      const orderParts: string[] = [];

      sortParts.forEach(part => {
        const [field, direction = 'asc'] = part.split(':');
        const dir = direction.toLowerCase() === 'desc' ? 'DESC' : 'ASC';
        orderParts.push(`${field} ${dir}`);
      });

      this.orderByClause = `ORDER BY ${orderParts.join(', ')}`;
    }
    return this;
  }

  limit(limit: number): this {
    if (limit && limit > 0) {
      this.limitClause = `LIMIT ${limit}`;
    }
    return this;
  }

  offset(offset: number): this {
    if (offset && offset > 0) {
      this.offsetClause = `OFFSET ${offset}`;
    }
    return this;
  }

  build(): { select: string; count: string } {
    const selectQuery = `SELECT ${this.selectClause} FROM ${this.table} ${this.whereClause} ${this.orderByClause} ${this.limitClause} ${this.offsetClause}`.trim();
    const countQuery = `SELECT COUNT(*) as total FROM ${this.table} ${this.whereClause}`.trim();

    return { select: selectQuery, count: countQuery };
  }

  getParams(): any[] {
    return [...this.params];
  }

  getCountParams(): any[] {
    return [...this.countParams];
  }
}

export function sqliteAdapter(config: SqliteAdapterConfig): DatabaseAdapter {
  let db: Database.Database | null = null;
  let queryCount = 0;
  let totalQueryTime = 0;

  const connect = async (): Promise<void> => {
    if (db) return;

    // Ensure directory exists
    const dbPath = config.url.startsWith('file:') ? config.url.slice(7) : config.url;
    const dir = path.dirname(dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    db = new Database(dbPath);

    // Performance optimizations
    db.pragma('journal_mode = WAL');
    db.pragma('synchronous = NORMAL');
    db.pragma('cache_size = 1000000000'); // 1GB cache
    db.pragma('foreign_keys = ON');
    db.pragma('temp_store = memory');
    db.pragma('mmap_size = 268435456'); // 256MB memory map

    // Create indexes for common queries (if tables exist)
    try {
      db.exec(`
        CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
        CREATE INDEX IF NOT EXISTS idx_users_roles ON users(json_extract(roles, '$[0]'));
        CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status);
        CREATE INDEX IF NOT EXISTS idx_posts_slug ON posts(slug);
        CREATE INDEX IF NOT EXISTS idx_posts_published_at ON posts(published_at);
      `);
    } catch (error) {
      // Ignore index creation errors during initial setup
    }
  };

  const disconnect = async (): Promise<void> => {
    if (db) {
      if (config.enableQueryLogging) {
        console.log(`Database stats: ${queryCount} queries, avg time: ${(totalQueryTime / queryCount).toFixed(2)}ms`);
      }
      db.close();
      db = null;
    }
  };

  const measureQuery = async <T>(operation: () => Promise<T>): Promise<T> => {
    const startTime = process.hrtime.bigint();
    try {
      const result = await operation();
      const endTime = process.hrtime.bigint();
      const duration = Number(endTime - startTime) / 1_000_000; // Convert to milliseconds

      queryCount++;
      totalQueryTime += duration;

      if (config.enableQueryLogging && duration > 10) {
        console.warn(`Slow query detected: ${duration.toFixed(2)}ms`);
      }

      return result;
    } catch (error) {
      const endTime = process.hrtime.bigint();
      const duration = Number(endTime - startTime) / 1_000_000;
      queryCount++;
      totalQueryTime += duration;
      throw error;
    }
  };

  const find = async (options: any): Promise<any> => {
    if (!db) await connect();

    return measureQuery(async () => {
      const { collection, where, limit = 10, page = 1, sort, depth = 0 } = options;

      // Performance optimization: early return for empty collections
      if (limit === 0) {
        return {
          docs: [],
          totalDocs: 0,
          limit: 0,
          totalPages: 0,
          page,
          hasPrevPage: false,
          hasNextPage: false,
          prevPage: null,
          nextPage: null,
        };
      }

      // Build optimized query
      const queryBuilder = new QueryBuilder(collection);
      queryBuilder.where(where).orderBy(sort).limit(limit).offset((page - 1) * limit);

      const query = queryBuilder.build();

      // Use prepared statements for performance and security
      const stmt = db!.prepare(query.select);
      const docs = stmt.all(...queryBuilder.getParams());

      // Optimized count query - only execute if we need pagination info
      let totalDocs = docs.length;
      let totalPages = 1;

      if (page > 1 || docs.length === limit) {
        const countStmt = db!.prepare(query.count);
        const countResult = countStmt.get(...queryBuilder.getCountParams()) as { total: number };
        totalDocs = countResult.total;
        totalPages = Math.ceil(totalDocs / limit);
      }

      return {
        docs,
        totalDocs,
        limit,
        totalPages,
        page,
        hasPrevPage: page > 1,
        hasNextPage: page * limit < totalDocs,
        prevPage: page > 1 ? page - 1 : null,
        nextPage: page * limit < totalDocs ? page + 1 : null,
      };
    });
  };

  const findByID = async (options: any): Promise<any> => {
    if (!db) await connect();

    return measureQuery(async () => {
      const { collection, id, depth = 0 } = options;

      try {
        // Use indexed lookup for better performance
        const stmt = db!.prepare(`SELECT * FROM ${collection} WHERE id = ? LIMIT 1`);
        const result = stmt.get(id);
        return result || null;
      } catch (error) {
        console.error(`Database findByID error for collection ${collection}, id ${id}:`, error);
        throw error;
      }
    });
  };

  const create = async (options: any): Promise<any> => {
    if (!db) await connect();

    return measureQuery(async () => {
      const { collection, data, depth = 0 } = options;

      try {
        const columns = Object.keys(data);
        const placeholders = columns.map(() => '?').join(', ');
        const values = columns.map(key => data[key]);

        const stmt = db!.prepare(
          `INSERT INTO ${collection} (${columns.join(', ')}) VALUES (${placeholders})`
        );

        const result = stmt.run(...values);

        // Return the created record
        if (config.idType === 'number' && result.lastInsertRowid) {
          return { ...data, id: result.lastInsertRowid };
        }

        return { ...data, id: data.id || result.lastInsertRowid };
      } catch (error) {
        console.error(`Database create error for collection ${collection}:`, error);
        throw error;
      }
    });
  };

  const update = async (options: any): Promise<any> => {
    if (!db) await connect();

    return measureQuery(async () => {
      const { collection, id, data, depth = 0 } = options;

      try {
        const columns = Object.keys(data);
        const setClause = columns.map(col => `${col} = ?`).join(', ');
        const values = columns.map(key => data[key]);
        values.push(id); // Add id for WHERE clause

        const stmt = db!.prepare(
          `UPDATE ${collection} SET ${setClause} WHERE id = ?`
        );

        const result = stmt.run(...values);

        if (result.changes === 0) {
          throw new Error(`No record found with id ${id} in collection ${collection}`);
        }

        // Return updated record
        return { ...data, id };
      } catch (error) {
        console.error(`Database update error for collection ${collection}, id ${id}:`, error);
        throw error;
      }
    });
  };

  const deleteRecord = async (options: any): Promise<any> => {
    if (!db) await connect();

    return measureQuery(async () => {
      const { collection, id } = options;

      try {
        const stmt = db!.prepare(`DELETE FROM ${collection} WHERE id = ?`);
        const result = stmt.run(id);

        if (result.changes === 0) {
          throw new Error(`No record found with id ${id} in collection ${collection}`);
        }

        return { id };
      } catch (error) {
        console.error(`Database delete error for collection ${collection}, id ${id}:`, error);
        throw error;
      }
    });
  };

  return {
    connect,
    disconnect,
    find,
    findByID,
    create,
    update,
    delete: deleteRecord,
  };
}