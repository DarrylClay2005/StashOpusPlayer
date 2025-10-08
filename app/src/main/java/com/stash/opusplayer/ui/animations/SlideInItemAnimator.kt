package com.stash.opusplayer.ui.animations

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.view.View
import androidx.recyclerview.widget.DefaultItemAnimator
import androidx.recyclerview.widget.RecyclerView

class SlideInItemAnimator : DefaultItemAnimator() {
    
    init {
        addDuration = 400
        removeDuration = 300
        moveDuration = 300
        changeDuration = 300
    }
    
    override fun animateAdd(holder: RecyclerView.ViewHolder): Boolean {
        // Reset view state
        holder.itemView.alpha = 0f
        holder.itemView.translationX = holder.itemView.rootView.width * 0.5f
        holder.itemView.scaleY = 0.8f
        
        // Animate in
        val fadeIn = ObjectAnimator.ofFloat(holder.itemView, "alpha", 0f, 1f)
        val slideIn = ObjectAnimator.ofFloat(holder.itemView, "translationX", 
            holder.itemView.translationX, 0f)
        val scaleY = ObjectAnimator.ofFloat(holder.itemView, "scaleY", 0.8f, 1f)
        
        fadeIn.duration = addDuration
        slideIn.duration = addDuration
        scaleY.duration = addDuration
        
        fadeIn.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationStart(animation: Animator) {
                dispatchAddStarting(holder)
            }
            
            override fun onAnimationEnd(animation: Animator) {
                animation.removeListener(this)
                holder.itemView.alpha = 1f
                holder.itemView.translationX = 0f
                holder.itemView.scaleY = 1f
                dispatchAddFinished(holder)
            }
        })
        
        fadeIn.start()
        slideIn.start()
        scaleY.start()
        
        return true
    }
    
    override fun animateRemove(holder: RecyclerView.ViewHolder): Boolean {
        val fadeOut = ObjectAnimator.ofFloat(holder.itemView, "alpha", 1f, 0f)
        val slideOut = ObjectAnimator.ofFloat(holder.itemView, "translationX", 
            0f, -holder.itemView.rootView.width * 0.3f)
        val scaleDown = ObjectAnimator.ofFloat(holder.itemView, "scaleY", 1f, 0.8f)
        
        fadeOut.duration = removeDuration
        slideOut.duration = removeDuration
        scaleDown.duration = removeDuration
        
        fadeOut.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationStart(animation: Animator) {
                dispatchRemoveStarting(holder)
            }
            
            override fun onAnimationEnd(animation: Animator) {
                animation.removeListener(this)
                holder.itemView.alpha = 1f
                holder.itemView.translationX = 0f
                holder.itemView.scaleY = 1f
                dispatchRemoveFinished(holder)
            }
        })
        
        fadeOut.start()
        slideOut.start()
        scaleDown.start()
        
        return true
    }
    
    override fun animateMove(
        holder: RecyclerView.ViewHolder,
        fromX: Int, fromY: Int,
        toX: Int, toY: Int
    ): Boolean {
        val deltaX = toX - fromX
        val deltaY = toY - fromY
        
        if (deltaX == 0 && deltaY == 0) {
            dispatchMoveFinished(holder)
            return false
        }
        
        holder.itemView.translationX = -deltaX.toFloat()
        holder.itemView.translationY = -deltaY.toFloat()
        
        val moveX = ObjectAnimator.ofFloat(holder.itemView, "translationX", 
            holder.itemView.translationX, 0f)
        val moveY = ObjectAnimator.ofFloat(holder.itemView, "translationY", 
            holder.itemView.translationY, 0f)
        
        moveX.duration = moveDuration
        moveY.duration = moveDuration
        
        moveX.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationStart(animation: Animator) {
                dispatchMoveStarting(holder)
            }
            
            override fun onAnimationEnd(animation: Animator) {
                animation.removeListener(this)
                holder.itemView.translationX = 0f
                holder.itemView.translationY = 0f
                dispatchMoveFinished(holder)
            }
        })
        
        moveX.start()
        moveY.start()
        
        return true
    }
    
    override fun animateChange(
        oldHolder: RecyclerView.ViewHolder?,
        newHolder: RecyclerView.ViewHolder?,
        fromLeft: Int, fromTop: Int,
        toLeft: Int, toTop: Int
    ): Boolean {
        if (oldHolder == newHolder) {
            return animateMove(oldHolder!!, fromLeft, fromTop, toLeft, toTop)
        }
        
        val fadeOut = oldHolder?.let {
            ObjectAnimator.ofFloat(it.itemView, "alpha", 1f, 0f).apply {
                duration = changeDuration / 2
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationStart(animation: Animator) {
                        dispatchChangeStarting(it, true)
                    }
                    override fun onAnimationEnd(animation: Animator) {
                        animation.removeListener(this)
                        it.itemView.alpha = 1f
                        dispatchChangeFinished(it, true)
                    }
                })
            }
        }
        
        val fadeIn = newHolder?.let {
            it.itemView.alpha = 0f
            ObjectAnimator.ofFloat(it.itemView, "alpha", 0f, 1f).apply {
                duration = changeDuration / 2
                startDelay = changeDuration / 2
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationStart(animation: Animator) {
                        dispatchChangeStarting(it, false)
                    }
                    override fun onAnimationEnd(animation: Animator) {
                        animation.removeListener(this)
                        it.itemView.alpha = 1f
                        dispatchChangeFinished(it, false)
                    }
                })
            }
        }
        
        fadeOut?.start()
        fadeIn?.start()
        
        return true
    }
}