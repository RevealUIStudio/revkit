#!/usr/bin/env tsx

/**
 * Performance Monitoring and Regression Detection
 *
 * Monitors application performance metrics and detects regressions.
 * Can be integrated into CI/CD pipelines.
 */

import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { createLogger } from '../../../core/src/logging';

interface PerformanceMetrics {
  timestamp: Date;
  buildTime: number;
  bundleSize: number;
  firstContentfulPaint?: number;
  largestContentfulPaint?: number;
  firstInputDelay?: number;
  cumulativeLayoutShift?: number;
  testExecutionTime: number;
  testCoverage: number;
}

interface PerformanceThresholds {
  maxBuildTime: number; // milliseconds
  maxBundleSize: number; // bytes
  maxFCP: number; // milliseconds
  maxLCP: number; // milliseconds
  maxFID: number; // milliseconds
  maxCLS: number; // score
  maxTestTime: number; // milliseconds
  minCoverage: number; // percentage
}

export class PerformanceMonitor {
  private logger = createLogger('PerformanceMonitor');
  private reportsDir = path.join(process.cwd(), '.reveal', 'performance-reports');
  private thresholds: PerformanceThresholds;

  constructor(thresholds: Partial<PerformanceThresholds> = {}) {
    this.thresholds = {
      maxBuildTime: 300000, // 5 minutes
      maxBundleSize: 5 * 1024 * 1024, // 5MB
      maxFCP: 2000, // 2 seconds
      maxLCP: 2500, // 2.5 seconds
      maxFID: 100, // 100ms
      maxCLS: 0.1, // 0.1 score
      maxTestTime: 600000, // 10 minutes
      minCoverage: 80, // 80%
      ...thresholds,
    };
    this.ensureReportsDir();
  }

  private ensureReportsDir() {
    if (!fs.existsSync(this.reportsDir)) {
      fs.mkdirSync(this.reportsDir, { recursive: true });
    }
  }

  /**
   * Run full performance analysis
   */
  async runAnalysis(options: {
    runBuild?: boolean;
    runTests?: boolean;
    runBundleAnalysis?: boolean;
    runE2E?: boolean;
  } = {}): Promise<{
    metrics: PerformanceMetrics;
    regressions: string[];
    passed: boolean;
  }> {
    const metrics: Partial<PerformanceMetrics> = {
      timestamp: new Date(),
    };

    const regressions: string[] = [];

    try {
      // Build analysis
      if (options.runBuild !== false) {
        this.logger.info('Running build performance analysis...');
        const buildMetrics = await this.measureBuildTime();
        metrics.buildTime = buildMetrics.time;
        metrics.bundleSize = buildMetrics.bundleSize;

        if (buildMetrics.time > this.thresholds.maxBuildTime) {
          regressions.push(`Build time exceeded threshold: ${buildMetrics.time}ms > ${this.thresholds.maxBuildTime}ms`);
        }

        if (buildMetrics.bundleSize > this.thresholds.maxBundleSize) {
          regressions.push(`Bundle size exceeded threshold: ${this.formatBytes(buildMetrics.bundleSize)} > ${this.formatBytes(this.thresholds.maxBundleSize)}`);
        }
      }

      // Test analysis
      if (options.runTests !== false) {
        this.logger.info('Running test performance analysis...');
        const testMetrics = await this.measureTestExecution();
        metrics.testExecutionTime = testMetrics.time;
        metrics.testCoverage = testMetrics.coverage;

        if (testMetrics.time > this.thresholds.maxTestTime) {
          regressions.push(`Test execution time exceeded threshold: ${testMetrics.time}ms > ${this.thresholds.maxTestTime}ms`);
        }

        if (testMetrics.coverage < this.thresholds.minCoverage) {
          regressions.push(`Test coverage below threshold: ${testMetrics.coverage}% < ${this.thresholds.minCoverage}%`);
        }
      }

      // Bundle analysis
      if (options.runBundleAnalysis !== false) {
        this.logger.info('Running bundle analysis...');
        const bundleMetrics = await this.analyzeBundleMetrics();
        Object.assign(metrics, bundleMetrics);
      }

      // E2E performance (if enabled)
      if (options.runE2E) {
        this.logger.info('Running E2E performance analysis...');
        const e2eMetrics = await this.measureE2EPerformance();
        Object.assign(metrics, e2eMetrics);
      }

      const completeMetrics = metrics as PerformanceMetrics;
      const passed = regressions.length === 0;

      // Save report
      await this.saveReport(completeMetrics, regressions);

      // Compare with previous runs
      const comparison = await this.compareWithPrevious(completeMetrics);
      if (comparison.regressions.length > 0) {
        regressions.push(...comparison.regressions);
      }

      return {
        metrics: completeMetrics,
        regressions,
        passed: regressions.length === 0,
      };

    } catch (error) {
      this.logger.error('Performance analysis failed:', error);
      throw error;
    }
  }

  private async measureBuildTime(): Promise<{ time: number; bundleSize: number }> {
    const startTime = Date.now();

    try {
      execSync('pnpm build --filter cms', {
        stdio: 'inherit',
        timeout: 10 * 60 * 1000, // 10 minutes
      });
    } catch (error) {
      throw new Error(`Build failed: ${error}`);
    }

    const buildTime = Date.now() - startTime;

    // Calculate bundle size
    const bundleSize = await this.calculateBundleSize();

    return { time: buildTime, bundleSize };
  }

  private async calculateBundleSize(): Promise<number> {
    const distDir = path.join(process.cwd(), 'apps', 'cms', '.next');

    if (!fs.existsSync(distDir)) {
      return 0;
    }

    let totalSize = 0;

    const calculateDirSize = (dirPath: string): number => {
      let size = 0;
      const items = fs.readdirSync(dirPath);

      for (const item of items) {
        const itemPath = path.join(dirPath, item);
        const stat = fs.statSync(itemPath);

        if (stat.isDirectory()) {
          size += calculateDirSize(itemPath);
        } else if (stat.isFile()) {
          size += stat.size;
        }
      }

      return size;
    };

    totalSize = calculateDirSize(distDir);

    return totalSize;
  }

  private async measureTestExecution(): Promise<{ time: number; coverage: number }> {
    const startTime = Date.now();

    try {
      execSync('pnpm test --filter @revealui/core', {
        stdio: 'pipe',
        timeout: 15 * 60 * 1000, // 15 minutes
      });
    } catch (error) {
      // Tests might fail but we still want metrics
      this.logger.warn('Tests failed but continuing with metrics collection');
    }

    const testTime = Date.now() - startTime;

    // Read coverage from coverage reports
    const coverage = await this.readCoverageReport();

    return { time: testTime, coverage };
  }

  private async readCoverageReport(): Promise<number> {
    const coveragePath = path.join(process.cwd(), 'coverage', 'coverage-summary.json');

    try {
      if (fs.existsSync(coveragePath)) {
        const coverageData = JSON.parse(fs.readFileSync(coveragePath, 'utf-8'));
        return Math.round(coverageData.total.lines.pct);
      }
    } catch (error) {
      this.logger.warn('Could not read coverage report:', error);
    }

    return 0;
  }

  private async analyzeBundleMetrics(): Promise<Partial<PerformanceMetrics>> {
    // This would integrate with the bundle monitor
    // For now, return empty metrics
    return {};
  }

  private async measureE2EPerformance(): Promise<Partial<PerformanceMetrics>> {
    // This would run Lighthouse or similar tools
    // For now, return empty metrics
    return {};
  }

  private async compareWithPrevious(current: PerformanceMetrics): Promise<{ regressions: string[] }> {
    const regressions: string[] = [];
    const reports = await this.getHistoricalReports();

    if (reports.length === 0) return { regressions };

    const previous = reports[reports.length - 1];

    // Check for significant regressions
    const buildTimeIncrease = ((current.buildTime - previous.buildTime) / previous.buildTime) * 100;
    if (buildTimeIncrease > 20) {
      regressions.push(`Build time increased by ${buildTimeIncrease.toFixed(1)}%`);
    }

    const bundleSizeIncrease = ((current.bundleSize - previous.bundleSize) / previous.bundleSize) * 100;
    if (bundleSizeIncrease > 10) {
      regressions.push(`Bundle size increased by ${bundleSizeIncrease.toFixed(1)}%`);
    }

    const testTimeIncrease = ((current.testExecutionTime - previous.testExecutionTime) / previous.testExecutionTime) * 100;
    if (testTimeIncrease > 15) {
      regressions.push(`Test execution time increased by ${testTimeIncrease.toFixed(1)}%`);
    }

    return { regressions };
  }

  private async getHistoricalReports(): Promise<PerformanceMetrics[]> {
    const reportFiles = fs.readdirSync(this.reportsDir)
      .filter(file => file.startsWith('perf-report-') && file.endsWith('.json'))
      .sort()
      .slice(-10); // Last 10 reports

    const reports: PerformanceMetrics[] = [];

    for (const file of reportFiles) {
      try {
        const content = fs.readFileSync(path.join(this.reportsDir, file), 'utf-8');
        const report = JSON.parse(content) as PerformanceMetrics;
        report.timestamp = new Date(report.timestamp);
        reports.push(report);
      } catch (error) {
        this.logger.warn(`Failed to load performance report ${file}:`, error);
      }
    }

    return reports;
  }

  private async saveReport(metrics: PerformanceMetrics, regressions: string[]): Promise<void> {
    const filename = `perf-report-${metrics.timestamp.toISOString().slice(0, 10)}.json`;
    const filepath = path.join(this.reportsDir, filename);

    const report = {
      metrics,
      regressions,
      passed: regressions.length === 0,
    };

    await fs.promises.writeFile(filepath, JSON.stringify(report, null, 2));
    this.logger.info(`Performance report saved to ${filepath}`);
  }

  private formatBytes(bytes: number): string {
    const units = ['B', 'KB', 'MB', 'GB'];
    let size = bytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return `${size.toFixed(1)} ${units[unitIndex]}`;
  }
}

/**
 * CLI runner for performance monitoring
 */
async function main() {
  const monitor = new PerformanceMonitor();

  const options = {
    runBuild: process.argv.includes('--build'),
    runTests: process.argv.includes('--tests'),
    runBundleAnalysis: process.argv.includes('--bundle'),
    runE2E: process.argv.includes('--e2e'),
  };

  // Run all if no specific options provided
  if (!options.runBuild && !options.runTests && !options.runBundleAnalysis && !options.runE2E) {
    options.runBuild = true;
    options.runTests = true;
    options.runBundleAnalysis = true;
  }

  try {
    const result = await monitor.runAnalysis(options);

    console.log('\n📊 Performance Analysis Report');
    console.log('===============================');
    console.log(`Build Time: ${result.metrics.buildTime}ms`);
    console.log(`Bundle Size: ${monitor['formatBytes'](result.metrics.bundleSize)}`);
    console.log(`Test Time: ${result.metrics.testExecutionTime}ms`);
    console.log(`Test Coverage: ${result.metrics.testCoverage}%`);
    console.log(`Status: ${result.passed ? '✅ PASSED' : '❌ FAILED'}`);

    if (result.regressions.length > 0) {
      console.log('\n🚨 Regressions Detected:');
      result.regressions.forEach(regression => console.log(`  - ${regression}`));
    }

    if (!result.passed) {
      process.exit(1);
    }

  } catch (error) {
    console.error('Performance monitoring failed:', error);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}