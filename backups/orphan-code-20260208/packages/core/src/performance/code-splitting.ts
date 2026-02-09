/**
 * Code Splitting and Lazy Loading Utilities
 *
 * Provides utilities for implementing code splitting, dynamic imports,
 * and lazy loading to improve application performance.
 */

import React, { ComponentType, lazy, Suspense, ReactNode } from 'react';
import { createLogger } from '../logging';

const logger = createLogger('CodeSplitting');

/**
 * Lazy load a React component with error boundary and loading fallback
 */
export function lazyLoad<T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>,
  fallback?: ReactNode,
  errorFallback?: ReactNode
): T {
  const LazyComponent = lazy(importFunc);

  const WrappedComponent = React.forwardRef<any, any>((props, ref) => (
    <Suspense fallback={fallback || <div>Loading...</div>}>
      <ErrorBoundary fallback={errorFallback}>
        <LazyComponent {...props} ref={ref} />
      </ErrorBoundary>
    </Suspense>
  ));

  WrappedComponent.displayName = `LazyLoad(${LazyComponent.displayName || 'Component'})`;

  return WrappedComponent as T;
}

/**
 * Create a lazy-loaded component with retry logic
 */
export function lazyLoadWithRetry<T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>,
  retries: number = 3,
  fallback?: ReactNode
): T {
  const LazyComponent = lazy(() => retryImport(importFunc, retries));

  const WrappedComponent = React.forwardRef<any, any>((props, ref) => (
    <Suspense fallback={fallback || <div>Loading...</div>}>
      <LazyComponent {...props} ref={ref} />
    </Suspense>
  ));

  WrappedComponent.displayName = `LazyLoadWithRetry(${LazyComponent.displayName || 'Component'})`;

  return WrappedComponent as T;
}

/**
 * Retry logic for dynamic imports
 */
async function retryImport<T>(
  importFunc: () => Promise<T>,
  retries: number
): Promise<T> {
  let lastError: Error;

  for (let i = 0; i <= retries; i++) {
    try {
      return await importFunc();
    } catch (error) {
      lastError = error as Error;
      logger.warn(`Import failed (attempt ${i + 1}/${retries + 1}):`, error);

      if (i < retries) {
        // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, Math.pow(2, i) * 1000));
      }
    }
  }

  throw lastError!;
}

/**
 * Error boundary for lazy-loaded components
 */
interface ErrorBoundaryState {
  hasError: boolean;
  error?: Error;
}

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
}

class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    logger.error('Lazy load error:', error, errorInfo);
    this.props.onError?.(error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || (
        <div className="p-4 border border-red-300 bg-red-50 rounded">
          <h3 className="text-red-800 font-medium">Component failed to load</h3>
          <p className="text-red-600 text-sm mt-1">
            {this.state.error?.message || 'An unexpected error occurred'}
          </p>
        </div>
      );
    }

    return this.props.children;
  }
}

/**
 * Preload a component for better UX
 */
export function preloadComponent(importFunc: () => Promise<any>): void {
  // Start loading in the background
  importFunc().catch(error => {
    logger.warn('Preload failed:', error);
  });
}

/**
 * Create a route-based code splitting point
 */
export function createRouteComponent<T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>,
  loadingComponent?: ReactNode
): T {
  return lazyLoad(
    importFunc,
    loadingComponent || <RouteLoadingSpinner />,
    <RouteErrorFallback />
  );
}

/**
 * Loading spinner for routes
 */
function RouteLoadingSpinner() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
    </div>
  );
}

/**
 * Error fallback for routes
 */
function RouteErrorFallback() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="text-center">
        <h2 className="text-2xl font-bold text-gray-900 mb-4">Something went wrong</h2>
        <p className="text-gray-600 mb-6">Failed to load this page. Please try again.</p>
        <button
          onClick={() => window.location.reload()}
          className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
        >
          Reload Page
        </button>
      </div>
    </div>
  );
}

/**
 * Bundle splitting utilities for common patterns
 */

// Split admin components
export const lazyLoadAdmin = <T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>
) => lazyLoad(importFunc, <div>Loading admin panel...</div>);

// Split heavy components (charts, editors, etc.)
export const lazyLoadHeavy = <T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>
) => lazyLoad(importFunc, <div>Loading component...</div>);

// Split modals and overlays
export const lazyLoadModal = <T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>
) => lazyLoad(importFunc, null); // No loading state for modals

/**
 * Intersection Observer based lazy loading for components
 */
export function useLazyComponent<T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>,
  options: IntersectionObserverInit = {}
): [React.ComponentType<any> | null, (node: Element | null) => void] {
  const [Component, setComponent] = React.useState<T | null>(null);
  const [isVisible, setIsVisible] = React.useState(false);

  const ref = React.useCallback((node: Element | null) => {
    if (!node) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !isVisible) {
          setIsVisible(true);
          importFunc().then(module => {
            setComponent(() => module.default);
          }).catch(error => {
            logger.error('Lazy component load failed:', error);
          });
        }
      },
      { threshold: 0.1, ...options }
    );

    observer.observe(node);

    return () => observer.disconnect();
  }, [isVisible, importFunc, options]);

  return [Component, ref];
}

/**
 * Prefetch utilities for route-based preloading
 */
export class RoutePreloader {
  private static prefetchedRoutes = new Set<string>();

  static preloadRoute(route: string, importFunc: () => Promise<any>) {
    if (this.prefetchedRoutes.has(route)) return;

    // Use requestIdleCallback if available, otherwise setTimeout
    const schedulePreload = window.requestIdleCallback ||
      ((callback: () => void) => setTimeout(callback, 100));

    schedulePreload(() => {
      importFunc().catch(error => {
        logger.debug(`Route preload failed for ${route}:`, error);
      });
      this.prefetchedRoutes.add(route);
    });
  }

  static isPrefetched(route: string): boolean {
    return this.prefetchedRoutes.has(route);
  }
}

/**
 * Bundle size monitoring integration
 */
export function withBundleTracking<T extends ComponentType<any>>(
  Component: T,
  bundleName: string
): T {
  // In development, track bundle loading
  if (process.env.NODE_ENV === 'development') {
    const startTime = performance.now();

    // Use a timeout to ensure the component has mounted
    setTimeout(() => {
      const loadTime = performance.now() - startTime;
      logger.debug(`Bundle loaded: ${bundleName} in ${loadTime.toFixed(2)}ms`);
    }, 0);
  }

  return Component;
}

/**
 * Create optimized chunks for common dependency groups
 */

// Vendor chunks
export const VENDOR_CHUNK = 'vendor';
export const UI_CHUNK = 'ui';
export const UTILS_CHUNK = 'utils';

// Webpack magic comments for chunk naming
export function createChunkImport<T>(
  importFunc: () => Promise<T>,
  chunkName: string
): () => Promise<T> {
  return () => importFunc();
}

// Usage examples:
/*
// Lazy load with chunk splitting
const AdminDashboard = lazyLoad(() =>
  createChunkImport(() => import('./AdminDashboard'), 'admin')
);

// Route-based splitting
const UserProfile = createRouteComponent(() =>
  import('./UserProfile')
);

// Heavy component with retry
const DataVisualization = lazyLoadWithRetry(() =>
  import('./DataVisualization'), 3
);

// Preload critical routes
RoutePreloader.preloadRoute('/dashboard', () => import('./Dashboard'));
*/