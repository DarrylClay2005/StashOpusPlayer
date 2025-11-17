package com.stash.opusplayer.ui.fragments

import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.bumptech.glide.Glide
import com.stash.opusplayer.R
import com.stash.opusplayer.cloud.CloudUserManager
import kotlinx.coroutines.launch

class ProfileFragment : Fragment() {
    private var avatarView: ImageView? = null
    private var emailText: TextView? = null
    private var usernameEdit: EditText? = null
    private var saveUsernameBtn: Button? = null
    private var resetPasswordBtn: Button? = null

    private val imagePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let { uploadAvatar(it) }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val root = inflater.inflate(R.layout.fragment_profile, container, false)
        avatarView = root.findViewById(R.id.profile_avatar)
        emailText = root.findViewById(R.id.profile_email)
        usernameEdit = root.findViewById(R.id.profile_username)
        saveUsernameBtn = root.findViewById(R.id.profile_save_username)
        resetPasswordBtn = root.findViewById(R.id.profile_reset_password)

        root.findViewById<View>(R.id.profile_change_avatar).setOnClickListener {
            imagePicker.launch("image/*")
        }

        saveUsernameBtn?.setOnClickListener {
            val name = usernameEdit?.text?.toString()?.trim().orEmpty()
            if (name.isNotEmpty()) {
                lifecycleScope.launch {
                    val ok = CloudUserManager.setUsername(name)
                    Toast.makeText(requireContext(), if (ok) "Username updated" else "Failed to update username", Toast.LENGTH_SHORT).show()
                }
            }
        }

        resetPasswordBtn?.setOnClickListener {
            // Use the email field as identifier
            val email = emailText?.text?.toString()?.trim().orEmpty()
            if (email.isNotEmpty()) {
                lifecycleScope.launch {
                    val ok = CloudUserManager.resetPassword(email)
                    Toast.makeText(requireContext(), if (ok) "Password reset email sent" else "Failed to send reset email", Toast.LENGTH_LONG).show()
                }
            }
        }

        return root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        // Populate from Amplify
        lifecycleScope.launch {
            try {
                com.amplifyframework.core.Amplify.Auth.fetchUserAttributes({ attrs ->
                    val email = attrs.firstOrNull { it.key.keyString == "email" }?.value
                    val name = attrs.firstOrNull { it.key.keyString == "name" }?.value
                    activity?.runOnUiThread {
                        emailText?.text = email ?: ""
                        usernameEdit?.setText(name ?: "")
                    }
                }, { _ -> })
            } catch (_: Exception) {}
            // Load avatar
            val file = CloudUserManager.downloadProfilePicture(requireContext())
            if (file != null && isAdded) {
                Glide.with(this@ProfileFragment).load(file).circleCrop().into(avatarView!!)
            }
        }
    }

    private fun uploadAvatar(uri: Uri) {
        lifecycleScope.launch {
            val ok = CloudUserManager.uploadProfilePicture(requireContext(), uri)
            if (ok) {
                Glide.with(this@ProfileFragment).load(uri).circleCrop().into(avatarView!!)
                Toast.makeText(requireContext(), "Profile picture updated", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(requireContext(), "Failed to upload avatar", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
