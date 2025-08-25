package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.fragment.app.Fragment
import com.stash.opusplayer.ui.MainActivity

class SettingsFragment : Fragment() {
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        
        val titleText = TextView(requireContext()).apply {
            text = "Settings"
            textSize = 24f
            setPadding(0, 0, 0, 32)
        }
        layout.addView(titleText)
        
        val backgroundButton = Button(requireContext()).apply {
            text = "Change Background Image"
            setOnClickListener {
                (activity as? MainActivity)?.pickBackgroundImage()
            }
        }
        layout.addView(backgroundButton)
        
        return layout
    }
}
