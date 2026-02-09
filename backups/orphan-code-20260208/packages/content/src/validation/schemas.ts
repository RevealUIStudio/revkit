/**
 * Validation schemas for RevealUI Content Engine operations
 */

import { z } from 'zod';

// ===== Base Schemas =====

export const idSchema = z.union([z.string(), z.number()]);

export const collectionSchema = z.string().min(1).max(100);

export const depthSchema = z.number().min(0).max(10).optional();

// ===== Where Clause Schemas =====

export const whereOperatorSchema = z.enum([
  'equals',
  'not_equals',
  'greater_than',
  'less_than',
  'greater_than_or_equal',
  'less_than_or_equal',
  'like',
  'in',
  'not_in',
  'contains',
  'not_contains',
]);

export const whereValueSchema = z.union([
  z.string(),
  z.number(),
  z.boolean(),
  z.date(),
  z.null(),
  z.array(z.union([z.string(), z.number(), z.boolean()])),
]);

export const whereConditionSchema = z.object({
  equals: whereValueSchema.optional(),
  not_equals: whereValueSchema.optional(),
  greater_than: whereValueSchema.optional(),
  less_than: whereValueSchema.optional(),
  greater_than_or_equal: whereValueSchema.optional(),
  less_than_or_equal: whereValueSchema.optional(),
  like: whereValueSchema.optional(),
  in: whereValueSchema.optional(),
  not_in: whereValueSchema.optional(),
  contains: whereValueSchema.optional(),
  not_contains: whereValueSchema.optional(),
});

export const whereClauseSchema = z.record(
  z.string(),
  z.union([whereValueSchema, whereConditionSchema])
);

// ===== Find Operation Schemas =====

export const findOptionsSchema = z.object({
  collection: collectionSchema,
  where: whereClauseSchema.optional(),
  limit: z.number().min(1).max(1000).optional().default(10),
  page: z.number().min(1).optional().default(1),
  sort: z.string().optional(),
  depth: depthSchema,
});

// ===== FindByID Operation Schema =====

export const findByIdOptionsSchema = z.object({
  collection: collectionSchema,
  id: idSchema,
  depth: depthSchema,
});

// ===== Create Operation Schema =====

export const createDataSchema = z.record(z.any());

export const createOptionsSchema = z.object({
  collection: collectionSchema,
  data: createDataSchema,
  depth: depthSchema,
});

// ===== Update Operation Schema =====

export const updateOptionsSchema = z.object({
  collection: collectionSchema,
  id: idSchema,
  data: createDataSchema,
  depth: depthSchema,
});

// ===== Delete Operation Schema =====

export const deleteOptionsSchema = z.object({
  collection: collectionSchema,
  id: idSchema,
});

// ===== Count Operation Schema =====

export const countOptionsSchema = z.object({
  collection: collectionSchema,
  where: whereClauseSchema.optional(),
});

// ===== Bulk Operation Schemas =====

export const bulkCreateOptionsSchema = z.object({
  collection: collectionSchema,
  data: z.array(createDataSchema),
  depth: depthSchema,
});

export const bulkUpdateOptionsSchema = z.object({
  collection: collectionSchema,
  where: whereClauseSchema,
  data: createDataSchema,
});

export const bulkDeleteOptionsSchema = z.object({
  collection: collectionSchema,
  where: whereClauseSchema,
});

// ===== Auth Operation Schemas =====

export const loginDataSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export const authArgsSchema = z.object({
  email: z.string().email().optional(),
  password: z.string().min(1).optional(),
  token: z.string().optional(),
  req: z.any().optional(), // Request object - validated separately
});

// ===== Global Operation Schemas =====

export const globalSlugSchema = z.string().min(1).max(100).regex(/^[a-zA-Z0-9_-]+$/);

export const findGlobalOptionsSchema = z.object({
  slug: globalSlugSchema,
  depth: depthSchema,
  req: z.any().optional(),
});

export const updateGlobalOptionsSchema = z.object({
  slug: globalSlugSchema,
  data: createDataSchema,
  depth: depthSchema,
  req: z.any().optional(),
});

// ===== Export Schemas =====

export const operationSchemas = {
  find: findOptionsSchema,
  findByID: findByIdOptionsSchema,
  create: createOptionsSchema,
  update: updateOptionsSchema,
  delete: deleteOptionsSchema,
  count: countOptionsSchema,
  bulkCreate: bulkCreateOptionsSchema,
  bulkUpdate: bulkUpdateOptionsSchema,
  bulkDelete: bulkDeleteOptionsSchema,
  login: loginDataSchema,
  auth: authArgsSchema,
  findGlobal: findGlobalOptionsSchema,
  updateGlobal: updateGlobalOptionsSchema,
} as const;