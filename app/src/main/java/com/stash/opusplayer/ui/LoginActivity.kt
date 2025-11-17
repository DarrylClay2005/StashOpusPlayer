package com.stash.opusplayer.ui

import android.app.Activity
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.stash.opusplayer.R
import android.widget.Button
import android.widget.EditText
import android.view.View
import android.widget.ProgressBar
import android.widget.Toast
import com.amplifyframework.core.Amplify
import com.amplifyframework.auth.options.AuthSignUpOptions
import com.amplifyframework.auth.AuthUserAttributeKey

class LoginActivity : AppCompatActivity() {
    private lateinit var emailField: EditText
    private lateinit var passwordField: EditText
    private lateinit var signInButton: Button
    private lateinit var signUpButton: Button
    private lateinit var confirmButton: Button
    private lateinit var resendButton: Button
    private lateinit var codeField: EditText
    private lateinit var progress: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)

        emailField = findViewById(R.id.login_email)
        passwordField = findViewById(R.id.login_password)
        signInButton = findViewById(R.id.login_button)
        signUpButton = findViewById(R.id.signup_button)
        confirmButton = findViewById(R.id.confirm_button)
        resendButton = findViewById(R.id.resend_button)
        codeField = findViewById(R.id.confirm_code)
        progress = findViewById(R.id.login_progress)

        signInButton.setOnClickListener {
            val email = emailField.text?.toString()?.trim().orEmpty()
            val password = passwordField.text?.toString().orEmpty()
            if (email.isEmpty() || password.isEmpty()) {
                Toast.makeText(this, "Enter email and password", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            signIn(email, password)
        }

        signUpButton.setOnClickListener {
            val email = emailField.text?.toString()?.trim().orEmpty()
            val password = passwordField.text?.toString().orEmpty()
            if (email.isEmpty() || password.isEmpty()) {
                Toast.makeText(this, "Enter email and password", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            signUp(email, password)
        }

        confirmButton.setOnClickListener {
            val email = emailField.text?.toString()?.trim().orEmpty()
            val code = codeField.text?.toString()?.trim().orEmpty()
            if (email.isEmpty() || code.isEmpty()) {
                Toast.makeText(this, "Enter email and confirmation code", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            confirmSignUp(email, code)
        }

        resendButton.setOnClickListener {
            val email = emailField.text?.toString()?.trim().orEmpty()
            if (email.isEmpty()) {
                Toast.makeText(this, "Enter email to resend code", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            resendCode(email)
        }
    }

    private fun signIn(username: String, password: String) {
        setLoading(true)
        Amplify.Auth.signIn(
            username,
            password,
            { result ->
                runOnUiThread {
                    setLoading(false)
                    if (result.isSignedIn) {
                        setResult(Activity.RESULT_OK)
                        finish()
                    } else {
                        Toast.makeText(this, "Sign-in failed", Toast.LENGTH_LONG).show()
                    }
                }
            },
            { error ->
                runOnUiThread {
                    setLoading(false)
                    Toast.makeText(this, "Error: ${error.localizedMessage ?: "Sign-in error"}", Toast.LENGTH_LONG).show()
                }
            }
        )
    }

    private fun signUp(email: String, password: String) {
        setLoading(true)
        val options = AuthSignUpOptions.builder()
            .userAttribute(AuthUserAttributeKey.email(), email)
            .build()
        Amplify.Auth.signUp(
            email,
            password,
            options,
            { result ->
                runOnUiThread {
                    setLoading(false)
                    if (result.isSignUpComplete) {
                        Toast.makeText(this, "Sign up successful. You can now sign in.", Toast.LENGTH_LONG).show()
                    } else {
                        Toast.makeText(this, "Sign up started. Check your email to confirm.", Toast.LENGTH_LONG).show()
                    }
                }
            },
            { error ->
                runOnUiThread {
                    setLoading(false)
                    Toast.makeText(this, "Sign up error: ${error.localizedMessage ?: "Unknown"}", Toast.LENGTH_LONG).show()
                }
            }
        )
    }

    private fun confirmSignUp(email: String, code: String) {
        setLoading(true)
        Amplify.Auth.confirmSignUp(
            email,
            code,
            { result ->
                runOnUiThread {
                    setLoading(false)
                    if (result.isSignUpComplete) {
                        Toast.makeText(this, "Confirmation successful. You can now sign in.", Toast.LENGTH_LONG).show()
                    } else {
                        Toast.makeText(this, "Confirmation step incomplete.", Toast.LENGTH_LONG).show()
                    }
                }
            },
            { error ->
                runOnUiThread {
                    setLoading(false)
                    Toast.makeText(this, "Confirm error: ${error.localizedMessage ?: "Unknown"}", Toast.LENGTH_LONG).show()
                }
            }
        )
    }

    private fun resendCode(email: String) {
        setLoading(true)
        Amplify.Auth.resendSignUpCode(
            email,
            { delivery ->
                runOnUiThread {
                    setLoading(false)
                    val dest = delivery.destination ?: "your email"
                    Toast.makeText(this, "Code sent to $dest", Toast.LENGTH_LONG).show()
                }
            },
            { error ->
                runOnUiThread {
                    setLoading(false)
                    Toast.makeText(this, "Resend error: ${error.localizedMessage ?: "Unknown"}", Toast.LENGTH_LONG).show()
                }
            }
        )
    }

    private fun setLoading(loading: Boolean) {
        progress.visibility = if (loading) View.VISIBLE else View.GONE
        signInButton.isEnabled = !loading
    }
}
