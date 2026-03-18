package com.hydrabin.connector.ui

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.hydrabin.connector.databinding.ActivityAuthBinding

class AuthActivity : AppCompatActivity() {

    private lateinit var binding: ActivityAuthBinding
    private lateinit var auth: FirebaseAuth
    private lateinit var firestore: FirebaseFirestore

    private var isLoginMode = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FirebaseApp.initializeApp(this)
        binding = ActivityAuthBinding.inflate(layoutInflater)
        setContentView(binding.root)

        auth = FirebaseAuth.getInstance()
        firestore = FirebaseFirestore.getInstance()

        // If already logged in, skip straight to Home
        auth.currentUser?.let {
            goToHome()
            return
        }

        binding.secondaryToggleButton.setOnClickListener {
            toggleMode()
        }

        binding.primaryButton.setOnClickListener {
            if (isLoginMode) {
                doLogin()
            } else {
                doSignup()
            }
        }
    }

    private fun toggleMode() {
        isLoginMode = !isLoginMode
        if (isLoginMode) {
            binding.modeText.text = "Login"
            binding.primaryButton.text = "Login"
            binding.secondaryToggleButton.text = "Don't have an account? Sign up"
            binding.nameInputLayout.visibility = View.GONE
        } else {
            binding.modeText.text = "Sign up"
            binding.primaryButton.text = "Create account"
            binding.secondaryToggleButton.text = "Already have an account? Login"
            binding.nameInputLayout.visibility = View.VISIBLE
        }
    }

    private fun doSignup() {
        val name = binding.nameEditText.text?.toString()?.trim().orEmpty()
        val email = binding.emailEditText.text?.toString()?.trim().orEmpty()
        val password = binding.passwordEditText.text?.toString()?.trim().orEmpty()

        if (name.isEmpty() || email.isEmpty() || password.length < 6) {
            Toast.makeText(this, "Enter name, valid email and 6+ char password", Toast.LENGTH_SHORT).show()
            return
        }

        setLoading(true)
        auth.createUserWithEmailAndPassword(email, password)
            .addOnSuccessListener { result ->
                val uid = result.user?.uid ?: return@addOnSuccessListener
                val userDoc = hashMapOf(
                    "name" to name,
                    "email" to email,
                    "points" to 0L,
                    "createdAt" to FieldValue.serverTimestamp()
                )
                firestore.collection("users").document(uid).set(userDoc)
                    .addOnSuccessListener {
                        setLoading(false)
                        goToHome()
                    }
                    .addOnFailureListener { e ->
                        setLoading(false)
                        Toast.makeText(this, e.localizedMessage ?: "Failed to create user record", Toast.LENGTH_SHORT).show()
                    }
            }
            .addOnFailureListener { e ->
                setLoading(false)
                Toast.makeText(this, e.localizedMessage ?: "Sign up failed", Toast.LENGTH_SHORT).show()
            }
    }

    private fun doLogin() {
        val email = binding.emailEditText.text?.toString()?.trim().orEmpty()
        val password = binding.passwordEditText.text?.toString()?.trim().orEmpty()

        if (email.isEmpty() || password.isEmpty()) {
            Toast.makeText(this, "Enter email and password", Toast.LENGTH_SHORT).show()
            return
        }

        setLoading(true)
        auth.signInWithEmailAndPassword(email, password)
            .addOnSuccessListener {
                setLoading(false)
                goToHome()
            }
            .addOnFailureListener { e ->
                setLoading(false)
                Toast.makeText(this, e.localizedMessage ?: "Login failed", Toast.LENGTH_SHORT).show()
            }
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.primaryButton.isEnabled = !loading
        binding.secondaryToggleButton.isEnabled = !loading
    }

    private fun goToHome() {
        startActivity(Intent(this, HomeActivity::class.java))
        finish()
    }
}
