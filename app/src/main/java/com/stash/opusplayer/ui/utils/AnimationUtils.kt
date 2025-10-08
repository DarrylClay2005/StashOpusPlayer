package com.stash.opusplayer.ui.utils

import android.animation.*
import android.content.Context
import android.view.View
import android.view.animation.*
import android.view.animation.Animation
import androidx.interpolator.view.animation.FastOutSlowInInterpolator
import com.stash.opusplayer.R
import kotlin.random.Random

object AnimationUtils {
    
    /**
     * Apply a bounce-in animation to a view
     */
    fun bounceIn(view: View, delay: Long = 0) {
        view.alpha = 0f
        view.scaleX = 0f
        view.scaleY = 0f
        
        view.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setStartDelay(delay)
            .setDuration(600)
            .setInterpolator(BounceInterpolator())
            .start()
    }
    
    /**
     * Apply an elastic scale animation to a view
     */
    fun elasticScale(view: View, onComplete: (() -> Unit)? = null) {
        val animator = AnimatorSet().apply {
            playSequentially(
                ObjectAnimator.ofFloat(view, "scaleX", 0.8f, 1.1f).apply {
                    duration = 200
                    interpolator = OvershootInterpolator()
                },
                ObjectAnimator.ofFloat(view, "scaleX", 1.1f, 1.0f).apply {
                    duration = 150
                    interpolator = DecelerateInterpolator()
                }
            )
            playSequentially(
                ObjectAnimator.ofFloat(view, "scaleY", 0.8f, 1.1f).apply {
                    duration = 200
                    interpolator = OvershootInterpolator()
                },
                ObjectAnimator.ofFloat(view, "scaleY", 1.1f, 1.0f).apply {
                    duration = 150
                    interpolator = DecelerateInterpolator()
                }
            )
        }
        
        animator.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                onComplete?.invoke()
            }
        })
        
        animator.start()
    }
    
    /**
     * Apply a pulse animation to a view (continuous)
     */
    fun startPulseAnimation(view: View): ObjectAnimator {
        return ObjectAnimator.ofFloat(view, "alpha", 1f, 0.7f, 1f).apply {
            duration = 1500
            repeatCount = ObjectAnimator.INFINITE
            repeatMode = ObjectAnimator.REVERSE
            interpolator = AccelerateDecelerateInterpolator()
            start()
        }
    }
    
    /**
     * Stop pulse animation
     */
    fun stopPulseAnimation(view: View, animator: ObjectAnimator?) {
        animator?.cancel()
        view.alpha = 1f
    }
    
    /**
     * Apply a wave ripple animation
     */
    fun waveRipple(view: View, onComplete: (() -> Unit)? = null) {
        val scaleAnimator = ObjectAnimator.ofFloat(view, "scaleX", 0f, 2f).apply {
            duration = 1500
            interpolator = DecelerateInterpolator()
        }
        
        val scaleYAnimator = ObjectAnimator.ofFloat(view, "scaleY", 0f, 2f).apply {
            duration = 1500
            interpolator = DecelerateInterpolator()
        }
        
        val alphaAnimator = ObjectAnimator.ofFloat(view, "alpha", 1f, 0f).apply {
            duration = 1500
            interpolator = AccelerateInterpolator()
        }
        
        val animatorSet = AnimatorSet().apply {
            playTogether(scaleAnimator, scaleYAnimator, alphaAnimator)
        }
        
        animatorSet.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                view.scaleX = 1f
                view.scaleY = 1f
                view.alpha = 1f
                onComplete?.invoke()
            }
        })
        
        animatorSet.start()
    }
    
    /**
     * Apply a shake animation for error feedback
     */
    fun shake(view: View, onComplete: (() -> Unit)? = null) {
        val shakeAnimator = ObjectAnimator.ofFloat(view, "translationX", 0f, 25f, -25f, 25f, -25f, 15f, -15f, 6f, -6f, 0f).apply {
            duration = 600
            interpolator = LinearInterpolator()
        }
        
        shakeAnimator.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                onComplete?.invoke()
            }
        })
        
        shakeAnimator.start()
    }
    
    /**
     * Apply a smooth scale-in animation
     */
    fun smoothScaleIn(view: View, delay: Long = 0, onComplete: (() -> Unit)? = null) {
        view.alpha = 0f
        view.scaleX = 0.5f
        view.scaleY = 0.5f
        
        view.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setStartDelay(delay)
            .setDuration(300)
            .setInterpolator(FastOutSlowInInterpolator())
            .withEndAction { onComplete?.invoke() }
            .start()
    }
    
    /**
     * Apply staggered animations to a list of views
     */
    fun staggeredAnimation(views: List<View>, animationType: AnimationType = AnimationType.SLIDE_UP, staggerDelay: Long = 100) {
        views.forEachIndexed { index, view ->
            val delay = index * staggerDelay
            when (animationType) {
                AnimationType.BOUNCE_IN -> bounceIn(view, delay)
                AnimationType.SMOOTH_SCALE -> smoothScaleIn(view, delay)
                AnimationType.SLIDE_UP -> slideUp(view, delay)
                AnimationType.FADE_IN -> fadeIn(view, delay)
            }
        }
    }
    
    /**
     * Apply a slide-up animation
     */
    fun slideUp(view: View, delay: Long = 0, onComplete: (() -> Unit)? = null) {
        view.alpha = 0f
        view.translationY = 200f
        
        view.animate()
            .alpha(1f)
            .translationY(0f)
            .setStartDelay(delay)
            .setDuration(500)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { onComplete?.invoke() }
            .start()
    }
    
    /**
     * Apply a fade-in animation
     */
    fun fadeIn(view: View, delay: Long = 0, onComplete: (() -> Unit)? = null) {
        view.alpha = 0f
        
        view.animate()
            .alpha(1f)
            .setStartDelay(delay)
            .setDuration(400)
            .withEndAction { onComplete?.invoke() }
            .start()
    }
    
    /**
     * Create a rotation animation for buttons on interaction
     */
    fun rotateOnClick(view: View) {
        view.animate()
            .rotationBy(360f)
            .setDuration(500)
            .setInterpolator(OvershootInterpolator())
            .start()
    }
    
    /**
     * Create a scale animation for button press feedback
     */
    fun scaleOnPress(view: View, onComplete: (() -> Unit)? = null) {
        val scaleDownX = ObjectAnimator.ofFloat(view, "scaleX", 1f, 0.95f).apply {
            duration = 100
            interpolator = AccelerateInterpolator()
        }
        
        val scaleDownY = ObjectAnimator.ofFloat(view, "scaleY", 1f, 0.95f).apply {
            duration = 100
            interpolator = AccelerateInterpolator()
        }
        
        val scaleUpX = ObjectAnimator.ofFloat(view, "scaleX", 0.95f, 1.05f).apply {
            duration = 100
            interpolator = DecelerateInterpolator()
        }
        
        val scaleUpY = ObjectAnimator.ofFloat(view, "scaleY", 0.95f, 1.05f).apply {
            duration = 100
            interpolator = DecelerateInterpolator()
        }
        
        val scaleNormalX = ObjectAnimator.ofFloat(view, "scaleX", 1.05f, 1f).apply {
            duration = 100
            interpolator = DecelerateInterpolator()
        }
        
        val scaleNormalY = ObjectAnimator.ofFloat(view, "scaleY", 1.05f, 1f).apply {
            duration = 100
            interpolator = DecelerateInterpolator()
        }
        
        val scaleDownSet = AnimatorSet().apply {
            playTogether(scaleDownX, scaleDownY)
        }
        
        val scaleUpSet = AnimatorSet().apply {
            playTogether(scaleUpX, scaleUpY)
        }
        
        val scaleNormalSet = AnimatorSet().apply {
            playTogether(scaleNormalX, scaleNormalY)
        }
        
        val animatorSet = AnimatorSet().apply {
            playSequentially(scaleDownSet, scaleUpSet, scaleNormalSet)
        }
        
        animatorSet.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                onComplete?.invoke()
            }
        })
        
        animatorSet.start()
    }
    
    /**
     * Create floating animation for floating action buttons
     */
    fun floatingAnimation(view: View): ObjectAnimator {
        return ObjectAnimator.ofFloat(view, "translationY", 0f, -20f, 0f).apply {
            duration = 2000
            repeatCount = ObjectAnimator.INFINITE
            repeatMode = ObjectAnimator.REVERSE
            interpolator = AccelerateDecelerateInterpolator()
            start()
        }
    }
    
    /**
     * Apply random sparkle animations around a view
     */
    fun sparkleEffect(context: Context, parent: android.view.ViewGroup, centerView: View, count: Int = 8) {
        val centerX = centerView.x + centerView.width / 2
        val centerY = centerView.y + centerView.height / 2
        
        repeat(count) {
            val sparkle = View(context).apply {
                setBackgroundResource(android.R.drawable.star_on)
                layoutParams = android.view.ViewGroup.LayoutParams(20, 20)
                alpha = 0f
                
                val angle = Random.nextFloat() * 2 * Math.PI
                val radius = 50 + Random.nextFloat() * 100
                val targetX = centerX + (kotlin.math.cos(angle) * radius).toFloat()
                val targetY = centerY + (kotlin.math.sin(angle) * radius).toFloat()
                
                x = centerX
                y = centerY
            }
            
            parent.addView(sparkle)
            
            val moveXAnimator = ObjectAnimator.ofFloat(sparkle, "translationX", 0f, Random.nextFloat() * 200 - 100).apply {
                duration = 1000 + Random.nextLong(500)
                interpolator = DecelerateInterpolator()
            }
            
            val moveYAnimator = ObjectAnimator.ofFloat(sparkle, "translationY", 0f, Random.nextFloat() * 200 - 100).apply {
                duration = 1000 + Random.nextLong(500)
                interpolator = DecelerateInterpolator()
            }
            
            val fadeAnimator = ObjectAnimator.ofFloat(sparkle, "alpha", 0f, 1f, 0f).apply {
                duration = 1000 + Random.nextLong(500)
            }
            
            val scaleXAnimator = ObjectAnimator.ofFloat(sparkle, "scaleX", 0.5f, 1.5f, 0f).apply {
                duration = 1000 + Random.nextLong(500)
                interpolator = AccelerateDecelerateInterpolator()
            }
            
            val scaleYAnimator = ObjectAnimator.ofFloat(sparkle, "scaleY", 0.5f, 1.5f, 0f).apply {
                duration = 1000 + Random.nextLong(500)
                interpolator = AccelerateDecelerateInterpolator()
            }
            
            val animatorSet = AnimatorSet().apply {
                playTogether(moveXAnimator, moveYAnimator, fadeAnimator, scaleXAnimator, scaleYAnimator)
            }
            
            animatorSet.addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    parent.removeView(sparkle)
                }
            })
            
            animatorSet.start()
        }
    }
    
    /**
     * Apply morphing animation between two shapes/colors
     */
    fun morphColor(view: View, fromColor: Int, toColor: Int, duration: Long = 300) {
        val colorAnimator = ValueAnimator.ofArgb(fromColor, toColor).apply {
            this.duration = duration
            addUpdateListener { animator ->
                view.setBackgroundColor(animator.animatedValue as Int)
            }
        }
        
        colorAnimator.start()
    }
    
    /**
     * Simple button press animation
     */
    fun animateButtonPress(view: View?) {
        view?.let {
            it.animate()
                .scaleX(0.95f)
                .scaleY(0.95f)
                .setDuration(100)
                .withEndAction {
                    it.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(100)
                        .start()
                }
                .start()
        }
    }
    
    enum class AnimationType {
        BOUNCE_IN,
        SMOOTH_SCALE,
        SLIDE_UP,
        FADE_IN
    }
}