package com.stash.opusplayer.ui.physics

import android.animation.*
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.animation.*
import androidx.dynamicanimation.animation.*
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.*
import kotlin.random.Random

/**
 * Physics-based animation engine for realistic UI interactions
 */
class PhysicsAnimationEngine(private val context: Context) {
    
    companion object {
        // Spring physics constants
        private const val SPRING_STIFFNESS = SpringForce.STIFFNESS_MEDIUM
        private const val SPRING_DAMPING = SpringForce.DAMPING_RATIO_LOW_BOUNCY
        private const val FLING_FRICTION = 2f
        
        // Animation properties
        private const val BUTTON_PRESS_SCALE = 0.95f
        private const val BUTTON_RELEASE_SCALE = 1.05f
        private const val RIPPLE_DURATION = 600L
        
        // Gravity settings
        private const val GRAVITY_STRENGTH = 9.8f
        private const val BOUNCE_FACTOR = 0.7f
    }
    
    private val activeAnimations = mutableSetOf<DynamicAnimation<*>>()
    
    /**
     * Spring-based button press animation
     */
    fun animateButtonPress(view: View, onComplete: (() -> Unit)? = null) {
        // Scale down with spring physics
        val scaleXAnim = SpringAnimation(view, DynamicAnimation.SCALE_X)
            .setSpring(SpringForce(BUTTON_PRESS_SCALE)
                .setStiffness(SPRING_STIFFNESS)
                .setDampingRatio(SPRING_DAMPING))
        
        val scaleYAnim = SpringAnimation(view, DynamicAnimation.SCALE_Y)
            .setSpring(SpringForce(BUTTON_PRESS_SCALE)
                .setStiffness(SPRING_STIFFNESS)
                .setDampingRatio(SPRING_DAMPING))
        
        // Add slight rotation for more natural feel
        val rotationAnim = SpringAnimation(view, DynamicAnimation.ROTATION)
            .setSpring(SpringForce(Random.nextFloat() * 4f - 2f) // -2° to +2°
                .setStiffness(SPRING_STIFFNESS * 0.5f)
                .setDampingRatio(SPRING_DAMPING))
        
        scaleXAnim.start()
        scaleYAnim.start()
        rotationAnim.start()
        
        activeAnimations.addAll(listOf(scaleXAnim, scaleYAnim, rotationAnim))
        
        // Release after a short delay
        view.postDelayed({
            animateButtonRelease(view, onComplete)
        }, 150)
    }
    
    /**
     * Spring-based button release animation
     */
    private fun animateButtonRelease(view: View, onComplete: (() -> Unit)? = null) {
        // Overshoot slightly then settle
        val scaleXAnim = SpringAnimation(view, DynamicAnimation.SCALE_X)
            .setSpring(SpringForce(1f)
                .setStiffness(SPRING_STIFFNESS)
                .setDampingRatio(SPRING_DAMPING))
        
        val scaleYAnim = SpringAnimation(view, DynamicAnimation.SCALE_Y)
            .setSpring(SpringForce(1f)
                .setStiffness(SPRING_STIFFNESS)
                .setDampingRatio(SPRING_DAMPING))
        
        val rotationAnim = SpringAnimation(view, DynamicAnimation.ROTATION)
            .setSpring(SpringForce(0f)
                .setStiffness(SPRING_STIFFNESS)
                .setDampingRatio(SPRING_DAMPING))
        
        var animationsCompleted = 0
        val totalAnimations = 3
        
        val animationListener = object : DynamicAnimation.OnAnimationEndListener {
            override fun onAnimationEnd(animation: DynamicAnimation<*>?, canceled: Boolean, value: Float, velocity: Float) {
                animationsCompleted++
                if (animationsCompleted >= totalAnimations) {
                    onComplete?.invoke()
                }
                activeAnimations.remove(animation)
            }
        }
        
        scaleXAnim.addEndListener(animationListener)
        scaleYAnim.addEndListener(animationListener)
        rotationAnim.addEndListener(animationListener)
        
        scaleXAnim.start()
        scaleYAnim.start()
        rotationAnim.start()
        
        activeAnimations.addAll(listOf(scaleXAnim, scaleYAnim, rotationAnim))
    }
    
    /**
     * Gravity-based falling animation for list items
     */
    fun animateItemFall(view: View, delay: Long = 0, onComplete: (() -> Unit)? = null) {
        view.alpha = 0f
        view.translationY = -200f
        view.rotation = Random.nextFloat() * 30f - 15f // Random rotation
        
        view.postDelayed({
            val fallAnimation = ObjectAnimator.ofFloat(view, "translationY", view.translationY, 0f).apply {
                duration = 800
                interpolator = BounceInterpolator()
            }
            
            val fadeAnimation = ObjectAnimator.ofFloat(view, "alpha", 0f, 1f).apply {
                duration = 400
                interpolator = AccelerateDecelerateInterpolator()
            }
            
            val rotationAnimation = ObjectAnimator.ofFloat(view, "rotation", view.rotation, 0f).apply {
                duration = 600
                interpolator = DecelerateInterpolator()
            }
            
            val animatorSet = AnimatorSet().apply {
                playTogether(fallAnimation, fadeAnimation, rotationAnimation)
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        onComplete?.invoke()
                    }
                })
            }
            
            animatorSet.start()
        }, delay)
    }
    
    /**
     * Momentum-based scrolling with realistic physics
     */
    fun animateFluidScrolling(recyclerView: RecyclerView, velocityX: Float, velocityY: Float) {
        val flingAnimationX = FlingAnimation(recyclerView, DynamicAnimation.SCROLL_X)
            .setStartVelocity(velocityX)
            .setFriction(FLING_FRICTION)
        
        val flingAnimationY = FlingAnimation(recyclerView, DynamicAnimation.SCROLL_Y)
            .setStartVelocity(velocityY)
            .setFriction(FLING_FRICTION)
        
        flingAnimationX.start()
        flingAnimationY.start()
        
        activeAnimations.addAll(listOf(flingAnimationX, flingAnimationY))
    }
    
    /**
     * Magnetic alignment animation - snaps views to grid
     */
    fun animateMagneticAlignment(view: View, targetX: Float, targetY: Float) {
        val springX = SpringAnimation(view, DynamicAnimation.X)
            .setSpring(SpringForce(targetX)
                .setStiffness(SPRING_STIFFNESS)
                .setDampingRatio(SPRING_DAMPING * 1.2f)) // More damped for snapping
        
        val springY = SpringAnimation(view, DynamicAnimation.Y)
            .setSpring(SpringForce(targetY)
                .setStiffness(SPRING_STIFFNESS)
                .setDampingRatio(SPRING_DAMPING * 1.2f))
        
        springX.start()
        springY.start()
        
        activeAnimations.addAll(listOf(springX, springY))
    }
    
    /**
     * Fluid dynamics - smooth natural motion curves
     */
    fun animateFluidMotion(view: View, targetX: Float, targetY: Float, duration: Long = 800) {
        val pathX = ValueAnimator.ofFloat(view.x, targetX)
        val pathY = ValueAnimator.ofFloat(view.y, targetY)
        
        // Custom interpolator that mimics fluid motion
        val fluidInterpolator = object : Interpolator {
            override fun getInterpolation(input: Float): Float {
                // Smooth curve that accelerates and decelerates naturally
                return (sin((input - 0.5f) * PI) / 2f + 0.5f).toFloat()
            }
        }
        
        pathX.apply {
            this.duration = duration
            interpolator = fluidInterpolator
            addUpdateListener { animation ->
                view.x = animation.animatedValue as Float
            }
        }
        
        pathY.apply {
            this.duration = duration
            interpolator = fluidInterpolator
            addUpdateListener { animation ->
                view.y = animation.animatedValue as Float
            }
        }
        
        pathX.start()
        pathY.start()
    }
    
    /**
     * Chain reaction animation - animate multiple views in sequence
     */
    fun animateChainReaction(views: List<View>, effect: ChainEffect, delayBetween: Long = 100) {
        views.forEachIndexed { index, view ->
            val delay = index * delayBetween
            when (effect) {
                ChainEffect.WAVE -> animateWaveEffect(view, delay)
                ChainEffect.FALL -> animateItemFall(view, delay)
                ChainEffect.SPRING -> animateSpringEffect(view, delay)
            }
        }
    }
    
    private fun animateWaveEffect(view: View, delay: Long) {
        view.postDelayed({
            val waveAnimation = ObjectAnimator.ofFloat(view, "scaleY", 1f, 1.2f, 1f).apply {
                duration = 400
                interpolator = AccelerateDecelerateInterpolator()
            }
            waveAnimation.start()
        }, delay)
    }
    
    private fun animateSpringEffect(view: View, delay: Long) {
        view.postDelayed({
            val springAnim = SpringAnimation(view, DynamicAnimation.SCALE_X)
                .setSpring(SpringForce(1.1f)
                    .setStiffness(SPRING_STIFFNESS)
                    .setDampingRatio(SPRING_DAMPING))
            
            springAnim.addEndListener { _, _, _, _ ->
                SpringAnimation(view, DynamicAnimation.SCALE_X)
                    .setSpring(SpringForce(1f)
                        .setStiffness(SPRING_STIFFNESS)
                        .setDampingRatio(SPRING_DAMPING))
                    .start()
            }
            
            springAnim.start()
            activeAnimations.add(springAnim)
        }, delay)
    }
    
    /**
     * Cancel all active physics animations
     */
    fun cancelAllAnimations() {
        activeAnimations.forEach { animation ->
            animation.cancel()
        }
        activeAnimations.clear()
    }
    
    /**
     * Release resources and cleanup
     */
    fun release() {
        cancelAllAnimations()
    }
    
    enum class ChainEffect {
        WAVE, FALL, SPRING
    }
}
