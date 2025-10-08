package com.stash.opusplayer.utils

import android.app.Activity
import android.content.Context
import android.content.res.Resources
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.ImageView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.doOnPreDraw
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.preference.PreferenceManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import kotlin.math.min

/**
 * Utility class for optimizing UI performance across the app
 * Provides methods for layout optimization, memory management, and responsive UI
 */
object UIPerformanceOptimizer {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val performanceMetrics = mutableMapOf<String, Long>()
    
    /**
     * Performance monitoring
     */
    fun startPerformanceTracking(tag: String) {
        performanceMetrics[tag] = System.currentTimeMillis()
    }
    
    fun endPerformanceTracking(tag: String): Long {
        val startTime = performanceMetrics.remove(tag) ?: return -1
        val duration = System.currentTimeMillis() - startTime
        android.util.Log.d("UIPerformance", "$tag took ${duration}ms")
        return duration
    }
    
    /**
     * Layout optimization methods
     */
    fun optimizeViewHierarchy(rootView: View) {
        optimizeViewRecursively(rootView)
    }
    
    private fun optimizeViewRecursively(view: View) {
        // Remove unnecessary background drawables on nested views
        if (view.parent is ViewGroup && view.background != null) {
            val parent = view.parent as ViewGroup
            if (parent.background != null) {
                // Parent has background, child doesn't need one unless it's different
                view.background = null
            }
        }
        
        // Enable hardware acceleration for complex views
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            when (view) {
                is ImageView -> {
                    view.setLayerType(View.LAYER_TYPE_HARDWARE, null)
                }
                is TextView -> {
                    // Only apply hardware acceleration for complex text views
                    if (view.text.length > 100 || view.typeface != null) {
                        view.setLayerType(View.LAYER_TYPE_HARDWARE, null)
                    }
                }
            }
        }
        
        // Recursively optimize child views
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                optimizeViewRecursively(view.getChildAt(i))
            }
        }
    }
    
    /**
     * RecyclerView optimizations
     */
    fun optimizeRecyclerView(recyclerView: RecyclerView) {
        // Enable view recycling optimizations
        recyclerView.setHasFixedSize(true)
        recyclerView.setItemViewCacheSize(20)
        recyclerView.setDrawingCacheEnabled(true)
        recyclerView.setDrawingCacheQuality(View.DRAWING_CACHE_QUALITY_HIGH)
        
        // Optimize scroll performance
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                when (newState) {
                    RecyclerView.SCROLL_STATE_IDLE -> {
                        // Resume image loading when scrolling stops
                        Glide.with(recyclerView.context).resumeRequests()
                    }
                    RecyclerView.SCROLL_STATE_DRAGGING, RecyclerView.SCROLL_STATE_SETTLING -> {
                        // Pause image loading during scroll for better performance
                        Glide.with(recyclerView.context).pauseRequests()
                    }
                }
            }
        })
        
        // Enable nested scrolling for better performance
        ViewCompat.setNestedScrollingEnabled(recyclerView, true)
    }
    
    /**
     * Image loading optimizations
     */
    fun optimizeImageLoading(context: Context, imageView: ImageView, imageUrl: String?, 
                           isScrolling: Boolean = false) {
        if (imageUrl.isNullOrBlank()) return
        
        val requestOptions = RequestOptions().apply {
            diskCacheStrategy(DiskCacheStrategy.RESOURCE)
            skipMemoryCache(false)
            
            if (isScrolling) {
                // Lower quality during scrolling for performance
                override(200, 200)
                diskCacheStrategy(DiskCacheStrategy.DATA)
            } else {
                // Full quality when not scrolling
                override(400, 400)
            }
        }
        
        Glide.with(context)
            .load(imageUrl)
            .apply(requestOptions)
            .into(imageView)
    }
    
    /**
     * Memory management
     */
    fun trimMemoryOnLowMemory(context: Context) {
        try {
            // Clear Glide memory cache
            Glide.get(context).clearMemory()
            
            // Force garbage collection (use sparingly)
            System.gc()
            
            android.util.Log.d("UIPerformance", "Memory trimmed due to low memory condition")
        } catch (e: Exception) {
            android.util.Log.e("UIPerformance", "Error trimming memory", e)
        }
    }
    
    /**
     * Fragment lifecycle optimizations
     */
    fun optimizeFragmentLifecycle(fragment: Fragment) {
        fragment.lifecycle.addObserver(object : LifecycleEventObserver {
            override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
                when (event) {
                    Lifecycle.Event.ON_PAUSE -> {
                        // Pause expensive operations
                        fragment.context?.let { context ->
                            Glide.with(context).pauseRequests()
                        }
                    }
                    Lifecycle.Event.ON_RESUME -> {
                        // Resume operations
                        fragment.context?.let { context ->
                            Glide.with(context).resumeRequests()
                        }
                    }
                    Lifecycle.Event.ON_DESTROY -> {
                        // Clean up resources
                        fragment.view?.let { view ->
                            clearViewReferences(view)
                        }
                    }
                    else -> {}
                }
            }
        })
    }
    
    /**
     * Activity optimizations
     */
    fun optimizeActivity(activity: Activity) {
        // Enable hardware acceleration
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            activity.window.setFlags(
                android.view.WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                android.view.WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            )
        }
        
        // Optimize window features
        activity.window.statusBarColor = android.graphics.Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.window.setDecorFitsSystemWindows(false)
        }
    }
    
    /**
     * Animation optimizations
     */
    fun optimizeAnimationsBasedOnSettings(context: Context) {
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        
        // Check performance mode setting
        val performanceMode = prefs.getBoolean("performance_mode_enabled", false)
        val batteryMode = prefs.getBoolean("battery_saver_animations", false)
        
        if (performanceMode || batteryMode) {
            // Reduce animation scale
            val durationScale = if (batteryMode) 0.5f else 0.75f
            
            // This would typically be applied through system animation settings
            // For app-level animations, we can create a global animation duration multiplier
            AnimationDurationManager.setGlobalDurationMultiplier(durationScale)
        }
    }
    
    /**
     * Layout measurement optimizations
     */
    fun optimizeLayoutMeasurement(view: View) {
        view.viewTreeObserver.addOnPreDrawListener(object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                view.viewTreeObserver.removeOnPreDrawListener(this)
                
                // Batch layout operations
                view.doOnPreDraw {
                    optimizeViewHierarchy(view)
                }
                return true
            }
        })
    }
    
    /**
     * Touch responsiveness optimizations
     */
    fun optimizeTouchResponsiveness(view: View) {
        // Reduce touch slop for better responsiveness
        ViewCompat.setAccessibilityDelegate(view, object : androidx.core.view.AccessibilityDelegateCompat() {
            override fun performAccessibilityAction(host: View, action: Int, args: android.os.Bundle?): Boolean {
                // Handle accessibility actions efficiently
                return super.performAccessibilityAction(host, action, args)
            }
        })
        
        // Optimize click handling
        view.setOnClickListener { clickedView ->
            // Add haptic feedback for better UX
            clickedView.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
            
            // Handle click efficiently on background thread if needed
            mainHandler.post {
                // Your click handling code here
            }
        }
    }
    
    /**
     * Screen density optimizations
     */
    fun optimizeForScreenDensity(context: Context): DisplayOptimizations {
        val displayMetrics = context.resources.displayMetrics
        val density = displayMetrics.density
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels
        
        return DisplayOptimizations(
            isHighDensity = density >= 3.0f,
            isLargeScreen = screenWidth >= 1080 && screenHeight >= 1920,
            recommendedImageSize = when {
                density >= 4.0f -> 512
                density >= 3.0f -> 384
                density >= 2.0f -> 256
                else -> 128
            },
            recommendedCacheSize = when {
                density >= 4.0f -> 50
                density >= 3.0f -> 30
                else -> 20
            }
        )
    }
    
    /**
     * Configuration change optimizations
     */
    fun optimizeForConfigurationChange(activity: Activity) {
        // Save fragment states efficiently for AppCompatActivity
        if (activity is androidx.appcompat.app.AppCompatActivity) {
            val fragmentManager = activity.supportFragmentManager
            for (fragment in fragmentManager.fragments) {
                if (fragment.isAdded && !fragment.isDetached) {
                    fragment.setRetainInstance(true)
                }
            }
        }
    }
    
    /**
     * Clear view references to prevent memory leaks
     */
    private fun clearViewReferences(view: View) {
        try {
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) {
                    clearViewReferences(view.getChildAt(i))
                }
            }
            
            // Clear listeners
            view.setOnClickListener(null)
            view.setOnLongClickListener(null)
            view.setOnTouchListener(null)
            
            // Clear animations
            view.clearAnimation()
            
        } catch (e: Exception) {
            android.util.Log.w("UIPerformance", "Error clearing view references", e)
        }
    }
    
    /**
     * Viewport-based loading optimization
     */
    fun setupViewportAwareLoading(recyclerView: RecyclerView, loadingCallback: (IntRange) -> Unit) {
        val layoutManager = recyclerView.layoutManager
        
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                
                if (layoutManager is androidx.recyclerview.widget.LinearLayoutManager) {
                    val firstVisible = layoutManager.findFirstVisibleItemPosition()
                    val lastVisible = layoutManager.findLastVisibleItemPosition()
                    
                    // Load items in viewport plus a buffer
                    val buffer = 5
                    val loadRange = (firstVisible - buffer).coerceAtLeast(0)..(lastVisible + buffer)
                    
                    loadingCallback(loadRange)
                }
            }
        })
    }
}

/**
 * Helper class for display optimization data
 */
data class DisplayOptimizations(
    val isHighDensity: Boolean,
    val isLargeScreen: Boolean,
    val recommendedImageSize: Int,
    val recommendedCacheSize: Int
)

/**
 * Global animation duration manager
 */
object AnimationDurationManager {
    private var globalMultiplier = 1.0f
    
    fun setGlobalDurationMultiplier(multiplier: Float) {
        globalMultiplier = multiplier.coerceIn(0.1f, 2.0f)
    }
    
    fun getOptimizedDuration(baseDuration: Long): Long {
        return (baseDuration * globalMultiplier).toLong()
    }
    
    fun getOptimizedDuration(baseDuration: Int): Int {
        return (baseDuration * globalMultiplier).toInt()
    }
}