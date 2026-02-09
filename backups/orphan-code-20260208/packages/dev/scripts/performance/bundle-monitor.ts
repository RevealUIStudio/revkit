#!/usr/bin/env tsx

/**
 * Bundle Size Monitoring and Analysis
 *
 * Monitors bundle sizes, tracks changes over time, and provides optimization recommendations.
 */

import fs from 'fs';
import path from 'path';
import { glob } from 'fast-glob';
import { createLogger } from '../../../core/src/logging';

interface BundleInfo {
  name: string;
  path: string;
  size: number;
  gzippedSize?: number;
  dependencies: string[];
  chunks: string[];
  timestamp: Date;
}

interface BundleReport {
  timestamp: Date;
  totalSize: number;
  totalGzippedSize: number;
  bundles: BundleInfo[];
  recommendations: string[];
  warnings: string[];
}

export class BundleMonitor {
  private logger = createLogger('BundleMonitor');
  private reportsDir = path.join(process.cwd(), '.reveal', 'bundle-reports');
  private threshold = {
    maxBundleSize: 500 * 1024, // 500KB
    maxTotalSize: 2 * 1024 * 1024, // 2MB
    warningSize: 200 * 1024, // 200KB
  };

  constructor() {
    this.ensureReportsDir();
  }

  private ensureReportsDir() {
    if (!fs.existsSync(this.reportsDir)) {
      fs.mkdirSync(this.reportsDir, { recursive: true });
    }
  }

  /**
   * Analyze build output and generate bundle report
   */
  async analyzeBuild(buildDir: string = 'dist'): Promise<BundleReport> {
    this.logger.info(`Analyzing bundle sizes in ${buildDir}`);

    const bundles = await this.findBundles(buildDir);
    const report: BundleReport = {
      timestamp: new Date(),
      totalSize: 0,
      totalGzippedSize: 0,
      bundles: [],
      recommendations: [],
      warnings: [],
    };

    for (const bundle of bundles) {
      const info = await this.analyzeBundle(bundle, buildDir);
      report.bundles.push(info);
      report.totalSize += info.size;
      if (info.gzippedSize) {
        report.totalGzippedSize += info.gzippedSize;
      }
    }

    report.recommendations = this.generateRecommendations(report);
    report.warnings = this.generateWarnings(report);

    await this.saveReport(report);

    this.logger.info(`Bundle analysis complete. Total size: ${this.formatBytes(report.totalSize)}`);
    return report;
  }

  private async findBundles(buildDir: string): Promise<string[]> {
    const patterns = [
      `${buildDir}/**/*.{js,css}`,
      `${buildDir}/**/*.chunk.*`,
      `${buildDir}/**/*.bundle.*`,
      `!${buildDir}/**/*.map`,
      `!${buildDir}/**/*.d.ts`,
    ];

    const files = await glob(patterns, { cwd: process.cwd() });
    return files.filter(file => {
      const stat = fs.statSync(file);
      return stat.isFile() && stat.size > 0;
    });
  }

  private async analyzeBundle(bundlePath: string, buildDir: string): Promise<BundleInfo> {
    const fullPath = path.resolve(bundlePath);
    const stat = fs.statSync(fullPath);

    const bundle: BundleInfo = {
      name: path.basename(bundlePath),
      path: bundlePath,
      size: stat.size,
      dependencies: [],
      chunks: [],
      timestamp: new Date(stat.mtime),
    };

    // Try to analyze the bundle content
    try {
      const content = fs.readFileSync(fullPath, 'utf-8');

      // Extract dependencies (basic analysis)
      const depMatches = content.match(/import\s+.*?\s+from\s+['"]([^'"]+)['"]/g) || [];
      bundle.dependencies = depMatches.map(match => {
        const dep = match.match(/from\s+['"]([^'"]+)['"]/)?.[1];
        return dep || '';
      }).filter(Boolean);

      // Check if it's a chunk
      if (bundle.name.includes('chunk') || bundle.name.includes('vendor')) {
        bundle.chunks = [bundle.name];
      }

    } catch (error) {
      // Binary file or read error, skip analysis
    }

    return bundle;
  }

  private generateRecommendations(report: BundleReport): string[] {
    const recommendations: string[] = [];

    if (report.totalSize > this.threshold.maxTotalSize) {
      recommendations.push(
        `Total bundle size (${this.formatBytes(report.totalSize)}) exceeds recommended maximum (${this.formatBytes(this.threshold.maxTotalSize)}). Consider code splitting.`
      );
    }

    const largeBundles = report.bundles.filter(b => b.size > this.threshold.maxBundleSize);
    if (largeBundles.length > 0) {
      recommendations.push(
        `Found ${largeBundles.length} bundle(s) larger than ${this.formatBytes(this.threshold.maxBundleSize)}: ${largeBundles.map(b => b.name).join(', ')}`
      );
    }

    // Check for duplicated dependencies
    const depCounts = new Map<string, number>();
    report.bundles.forEach(bundle => {
      bundle.dependencies.forEach(dep => {
        depCounts.set(dep, (depCounts.get(dep) || 0) + 1);
      });
    });

    const duplicatedDeps = Array.from(depCounts.entries())
      .filter(([, count]) => count > 1)
      .map(([dep]) => dep);

    if (duplicatedDeps.length > 0) {
      recommendations.push(
        `Consider extracting shared dependencies to reduce duplication: ${duplicatedDeps.slice(0, 5).join(', ')}${duplicatedDeps.length > 5 ? ` and ${duplicatedDeps.length - 5} more` : ''}`
      );
    }

    return recommendations;
  }

  private generateWarnings(report: BundleReport): string[] {
    const warnings: string[] = [];

    const warningBundles = report.bundles.filter(b => b.size > this.threshold.warningSize && b.size <= this.threshold.maxBundleSize);
    if (warningBundles.length > 0) {
      warnings.push(
        `Found ${warningBundles.length} bundle(s) approaching size limits: ${warningBundles.map(b => `${b.name} (${this.formatBytes(b.size)})`).join(', ')}`
      );
    }

    return warnings;
  }

  private async saveReport(report: BundleReport): Promise<void> {
    const filename = `bundle-report-${report.timestamp.toISOString().slice(0, 10)}.json`;
    const filepath = path.join(this.reportsDir, filename);

    await fs.promises.writeFile(filepath, JSON.stringify(report, null, 2));
    this.logger.info(`Bundle report saved to ${filepath}`);
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

  /**
   * Compare current report with previous reports
   */
  async compareReports(currentReport: BundleReport): Promise<{
    sizeChange: number;
    percentageChange: number;
    trend: 'increasing' | 'decreasing' | 'stable';
  }> {
    const reports = await this.getHistoricalReports();
    if (reports.length === 0) {
      return { sizeChange: 0, percentageChange: 0, trend: 'stable' };
    }

    const previousReport = reports[reports.length - 1];
    const sizeChange = currentReport.totalSize - previousReport.totalSize;
    const percentageChange = (sizeChange / previousReport.totalSize) * 100;

    let trend: 'increasing' | 'decreasing' | 'stable' = 'stable';
    if (Math.abs(percentageChange) > 5) {
      trend = percentageChange > 0 ? 'increasing' : 'decreasing';
    }

    return { sizeChange, percentageChange, trend };
  }

  private async getHistoricalReports(): Promise<BundleReport[]> {
    const reportFiles = await glob('bundle-report-*.json', {
      cwd: this.reportsDir,
    });

    const reports: BundleReport[] = [];
    for (const file of reportFiles) {
      try {
        const content = await fs.promises.readFile(path.join(this.reportsDir, file), 'utf-8');
        const report = JSON.parse(content) as BundleReport;
        report.timestamp = new Date(report.timestamp);
        reports.push(report);
      } catch (error) {
        this.logger.warn(`Failed to load report ${file}: ${error}`);
      }
    }

    return reports.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
  }

  /**
   * Generate optimization recommendations
   */
  generateOptimizationPlan(report: BundleReport): {
    immediate: string[];
    shortTerm: string[];
    longTerm: string[];
  } {
    const immediate: string[] = [];
    const shortTerm: string[] = [];
    const longTerm: string[] = [];

    // Immediate actions for critical issues
    if (report.totalSize > this.threshold.maxTotalSize) {
      immediate.push('Implement route-based code splitting');
      immediate.push('Enable dynamic imports for large components');
      immediate.push('Remove unused dependencies');
    }

    // Short-term optimizations
    const largeBundles = report.bundles.filter(b => b.size > this.threshold.maxBundleSize);
    if (largeBundles.length > 0) {
      shortTerm.push('Split large bundles into smaller chunks');
      shortTerm.push('Implement lazy loading for heavy components');
      shortTerm.push('Use tree shaking to eliminate dead code');
    }

    // Long-term architectural improvements
    longTerm.push('Implement micro-frontend architecture');
    longTerm.push('Set up bundle size budgets and CI checks');
    longTerm.push('Create shared component library');
    longTerm.push('Implement progressive loading strategies');

    return { immediate, shortTerm, longTerm };
  }
}

/**
 * CLI runner for bundle monitoring
 */
async function main() {
  const monitor = new BundleMonitor();
  const buildDir = process.argv[2] || 'dist';

  try {
    const report = await monitor.analyzeBuild(buildDir);
    const comparison = await monitor.compareReports(report);
    const optimizationPlan = monitor.generateOptimizationPlan(report);

    console.log('\n📊 Bundle Analysis Report');
    console.log('========================');
    console.log(`Total Size: ${monitor['formatBytes'](report.totalSize)}`);
    console.log(`Bundles: ${report.bundles.length}`);
    console.log(`Size Trend: ${comparison.trend} (${comparison.percentageChange.toFixed(1)}%)`);

    if (report.warnings.length > 0) {
      console.log('\n⚠️  Warnings:');
      report.warnings.forEach(warning => console.log(`  - ${warning}`));
    }

    if (report.recommendations.length > 0) {
      console.log('\n💡 Recommendations:');
      report.recommendations.forEach(rec => console.log(`  - ${rec}`));
    }

    console.log('\n🚀 Optimization Plan:');
    console.log('Immediate:');
    optimizationPlan.immediate.forEach(action => console.log(`  - ${action}`));

    console.log('Short-term:');
    optimizationPlan.shortTerm.forEach(action => console.log(`  - ${action}`));

    console.log('Long-term:');
    optimizationPlan.longTerm.forEach(action => console.log(`  - ${action}`));

  } catch (error) {
    console.error('Bundle analysis failed:', error);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}