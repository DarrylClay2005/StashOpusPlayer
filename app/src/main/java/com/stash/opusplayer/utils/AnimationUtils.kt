package com.stash.opusplayer.utils

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.animation.AnimationUtils as AndroidAnimationUtils
import android.view.animation.Animation
import android.view.animation.DecelerateInterpolator
import android.view.animation.AccelerateInterpolator
import android.view.animation.BounceInterpolator
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentTransaction
import com.stash.opusplayer.R
import com.stash.opusplayer.ui.physics.PhysicsAnimationEngine

object AnimationUtils {
    
    // Physics animation engine - lazy initialized to avoid circular dependencies
    private var physicsEngine: PhysicsAnimationEngine? = null
    
    fun setPhysicsEngine(engine: PhysicsAnimationEngine) {
        physicsEngine = engine
    }
    
    // Activity transition animations
    fun startActivityWithSlideIn(activity: Activity) {
        activity.overridePendingTransition(R.anim.slide_in_right, R.anim.slide_out_left)
    }
    
    fun finishActivityWithSlideOut(activity: Activity) {
        activity.overridePendingTransition(R.anim.slide_in_left, R.anim.slide_out_right)
    }
    
    fun startActivityWithFade(activity: Activity) {
        activity.overridePendingTransition(R.anim.fade_in, R.anim.fade_out)
    }
    
    fun startActivityWithScale(activity: Activity) {
        activity.overridePendingTransition(R.anim.scale_fade_in, R.anim.scale_fade_out)
    }
    
    // Fragment transition animations
    fun setFragmentTransitions(transaction: FragmentTransaction, isForward: Boolean = true) {
        if (isForward) {
            transaction.setCustomAnimations(
                R.anim.slide_in_right,
                R.anim.slide_out_left,
                R.anim.slide_in_left,
                R.anim.slide_out_right
            )
        } else {
            transaction.setCustomAnimations(
                R.anim.slide_in_left,
                R.anim.slide_out_right,
                R.anim.slide_in_right,
                R.anim.slide_out_left
            )
        }
    }
    
    fun setFragmentFadeTransitions(transaction: FragmentTransaction) {
        transaction.setCustomAnimations(
            R.anim.fade_in,
            R.anim.fade_out,
            R.anim.fade_in,
            R.anim.fade_out
        )
    }
    
    fun setFragmentVerticalTransitions(transaction: FragmentTransaction) {
        transaction.setCustomAnimations(
            R.anim.slide_up,
            R.anim.fade_out,
            R.anim.fade_in,
            R.anim.slide_down
        )
    }
    
    // View animations
    fun animateViewScale(view: View, fromScale: Float = 1.0f, toScale: Float = 1.1f, duration: Long = 200) {
        view.animate()
            .scaleX(toScale)
            .scaleY(toScale)
            .setDuration(duration)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction {
                view.animate()
                    .scaleX(fromScale)
                    .scaleY(fromScale)
                    .setDuration(duration)
                    .setInterpolator(AccelerateInterpolator())
                    .start()
            }
            .start()
    }
    
    fun animateButtonPress(view: View, onAnimationEnd: (() -> Unit)? = null) {
        // Try to use physics engine first, fallback to traditional animation
        physicsEngine?.let { engine ->
            engine.animateButtonPress(view, onAnimationEnd)
        } ?: run {
            // Fallback to traditional animation
            view.animate()
                .scaleX(0.95f)
                .scaleY(0.95f)
                .setDuration(100)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction {
                    view.animate()
                        .scaleX(1.0f)
                        .scaleY(1.0f)
                        .setDuration(150)
                        .setInterpolator(BounceInterpolator())
                        .withEndAction { onAnimationEnd?.invoke() }
                        .start()
                }
                .start()
        }
    }
    
    fun fadeIn(view: View, duration: Long = 300, onAnimationEnd: (() -> Unit)? = null) {
        view.alpha = 0f
        view.visibility = View.VISIBLE
        view.animate()
            .alpha(1f)
            .setDuration(duration)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { onAnimationEnd?.invoke() }
            .start()
    }
    
    fun fadeOut(view: View, duration: Long = 300, onAnimationEnd: (() -> Unit)? = null) {
        view.animate()
            .alpha(0f)
            .setDuration(duration)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction {
                view.visibility = View.GONE
                onAnimationEnd?.invoke()
            }
            .start()
    }
    
    fun slideInFromRight(view: View, duration: Long = 350, onAnimationEnd: (() -> Unit)? = null) {
        view.translationX = view.width.toFloat()
        view.visibility = View.VISIBLE
        view.animate()
            .translationX(0f)
            .setDuration(duration)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { onAnimationEnd?.invoke() }
            .start()
    }
    
    fun slideOutToRight(view: View, duration: Long = 350, onAnimationEnd: (() -> Unit)? = null) {
        view.animate()
            .translationX(view.width.toFloat())
            .setDuration(duration)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction {
                view.visibility = View.GONE
                view.translationX = 0f
                onAnimationEnd?.invoke()
            }
            .start()
    }
    
    fun slideInFromBottom(view: View, duration: Long = 350, onAnimationEnd: (() -> Unit)? = null) {
        view.translationY = view.height.toFloat()
        view.visibility = View.VISIBLE
        view.animate()
            .translationY(0f)
            .setDuration(duration)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { onAnimationEnd?.invoke() }
            .start()
    }
    
    fun slideOutToBottom(view: View, duration: Long = 350, onAnimationEnd: (() -> Unit)? = null) {
        view.animate()
            .translationY(view.height.toFloat())
            .setDuration(duration)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction {
                view.visibility = View.GONE
                view.translationY = 0f
                onAnimationEnd?.invoke()
            }
            .start()
    }
    
    fun bounceView(view: View, scale: Float = 1.2f, duration: Long = 600) {
        view.animate()
            .scaleX(scale)
            .scaleY(scale)
            .setDuration(duration / 2)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction {
                view.animate()
                    .scaleX(1.0f)
                    .scaleY(1.0f)
                    .setDuration(duration / 2)
                    .setInterpolator(BounceInterpolator())
                    .start()
            }
            .start()
    }
    
    // Methods used by RevampedMiniPlayerView
    fun animateSlideOut(view: View, toRight: Boolean, onComplete: (() -> Unit)? = null) {
        val translationX = if (toRight) view.width.toFloat() else -view.width.toFloat()
        view.animate()
            .translationX(translationX)
            .setDuration(300)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction { onComplete?.invoke() }
            .start()
    }
    
    fun animateSlideIn(view: View, fromRight: Boolean, onComplete: (() -> Unit)? = null) {
        val startX = if (fromRight) view.width.toFloat() else -view.width.toFloat()
        view.translationX = startX
        view.animate()
            .translationX(0f)
            .setDuration(300)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { onComplete?.invoke() }
            .start()
    }
    
    fun animateFadeIn(view: View, onComplete: (() -> Unit)? = null) {
        view.alpha = 0f
        view.visibility = View.VISIBLE
        view.animate()
            .alpha(1f)
            .setDuration(300)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { onComplete?.invoke() }
            .start()
    }
    
    fun animateFadeOut(view: View, onComplete: (() -> Unit)? = null) {
        view.animate()
            .alpha(0f)
            .setDuration(300)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction { 
                view.visibility = View.GONE
                onComplete?.invoke() 
            }
            .start()
    }
    
    fun pulseView(view: View, pulseCount: Int = 3, duration: Long = 400) {
        var count = 0
        
        fun pulse() {
            if (count < pulseCount) {
                count++
                view.animate()
                    .scaleX(1.1f)
                    .scaleY(1.1f)
                    .setDuration(duration / 2)
                    .setInterpolator(DecelerateInterpolator())
                    .withEndAction {
                        view.animate()
                            .scaleX(1.0f)
                            .scaleY(1.0f)
                            .setDuration(duration / 2)
                            .setInterpolator(AccelerateInterpolator())
                            .withEndAction { pulse() }
                            .start()
                    }
                    .start()
            }
        }
        
        pulse()
    }
    
    fun rotateView(view: View, degrees: Float = 360f, duration: Long = 500) {
        view.animate()
            .rotation(view.rotation + degrees)
            .setDuration(duration)
            .setInterpolator(DecelerateInterpolator())
            .start()
    }
    
    // List item animations with stagger effect
    fun animateListItems(views: List<View>, startDelay: Long = 0, itemDelay: Long = 50) {
        physicsEngine?.let { engine ->
            // Use physics-based falling animation
            views.forEachIndexed { index, view ->
                val delay = startDelay + (index * itemDelay)
                engine.animateItemFall(view, delay)
            }
        } ?: run {
            // Fallback to traditional animation
            views.forEachIndexed { index, view ->
                view.alpha = 0f
                view.translationY = 50f
                view.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setStartDelay(startDelay + (index * itemDelay))
                    .setDuration(400)
                    .setInterpolator(DecelerateInterpolator())
                    .start()
            }
        }
    }
    
    /**
     * Enhanced list animations with physics effects
     */
    fun animateListWithPhysics(views: List<View>, effect: PhysicsAnimationEngine.ChainEffect = PhysicsAnimationEngine.ChainEffect.FALL) {
        physicsEngine?.animateChainReaction(views, effect)
    }
    
    // Loading animation for progress indicators
    fun startLoadingAnimation(view: View) {
        val animation = AndroidAnimationUtils.loadAnimation(view.context, R.anim.rotate_360)
        view.startAnimation(animation)
    }
    
    fun stopLoadingAnimation(view: View) {
        view.clearAnimation()
    }
}