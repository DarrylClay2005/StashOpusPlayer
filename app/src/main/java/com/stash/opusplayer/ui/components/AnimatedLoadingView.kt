package com.stash.opusplayer.ui.components

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import com.stash.opusplayer.databinding.ComponentAnimatedLoadingBinding
import com.stash.opusplayer.utils.AnimationUtils

class AnimatedLoadingView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    
    private val binding: ComponentAnimatedLoadingBinding =
        ComponentAnimatedLoadingBinding.inflate(LayoutInflater.from(context), this, true)
    
    private var isAnimating = false
    
    init {
        visibility = View.GONE
    }
    
    fun show(message: String = "Loading...", animated: Boolean = true) {
        binding.loadingText.text = message
        
        if (animated) {
            AnimationUtils.fadeIn(this) {
                startLoadingAnimation()
            }
        } else {
            visibility = View.VISIBLE
            startLoadingAnimation()
        }
    }
    
    fun hide(animated: Boolean = true) {
        stopLoadingAnimation()
        
        if (animated) {
            AnimationUtils.fadeOut(this) {
                visibility = View.GONE
            }
        } else {
            visibility = View.GONE
        }
    }
    
    fun updateMessage(message: String) {
        binding.loadingText.text = message
        
        // Add a subtle text change animation
        binding.loadingText.animate()
            .alpha(0.7f)
            .setDuration(150)
            .withEndAction {
                binding.loadingText.animate()
                    .alpha(1.0f)
                    .setDuration(150)
                    .start()
            }
            .start()
    }
    
    private fun startLoadingAnimation() {
        if (isAnimating) return
        
        isAnimating = true
        
        // Rotate the loading icon
        AnimationUtils.startLoadingAnimation(binding.loadingIcon)
        
        // Pulsate the text
        AnimationUtils.pulseView(binding.loadingText, Int.MAX_VALUE, 1000)
        
        // Add floating dots animation
        animateLoadingDots()
    }
    
    private fun stopLoadingAnimation() {
        if (!isAnimating) return
        
        isAnimating = false
        
        AnimationUtils.stopLoadingAnimation(binding.loadingIcon)
        binding.loadingText.clearAnimation()
        
        // Stop dots animation
        binding.dot1.clearAnimation()
        binding.dot2.clearAnimation() 
        binding.dot3.clearAnimation()
    }
    
    private fun animateLoadingDots() {
        if (!isAnimating) return
        
        val dots = listOf(binding.dot1, binding.dot2, binding.dot3)
        
        dots.forEachIndexed { index, dot ->
            dot.animate()
                .translationY(-20f)
                .setDuration(600)
                .setStartDelay((index * 200).toLong())
                .withEndAction {
                    if (isAnimating) {
                        dot.animate()
                            .translationY(0f)
                            .setDuration(600)
                            .withEndAction {
                                if (isAnimating) {
                                    // Loop the animation
                                    post { animateLoadingDots() }
                                }
                            }
                            .start()
                    }
                }
                .start()
        }
    }
    
    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopLoadingAnimation()
    }
}