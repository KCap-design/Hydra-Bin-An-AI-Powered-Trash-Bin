package com.hydrabin.connector.ui

import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.airbnb.lottie.LottieAnimationView
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.hydrabin.connector.R
import com.hydrabin.connector.databinding.ActivityHomeBinding
import com.hydrabin.connector.ui.adapter.LeaderboardAdapter
import com.hydrabin.connector.ui.model.LeaderboardItem

class HomeActivity : AppCompatActivity() {

    private lateinit var binding: ActivityHomeBinding
    private lateinit var auth: FirebaseAuth
    private lateinit var firestore: FirebaseFirestore

    private var userListenerRegistration: ListenerRegistration? = null
    private var leaderboardListenerRegistration: ListenerRegistration? = null
    private var lastPoints: Long? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityHomeBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)

        auth = FirebaseAuth.getInstance()
        firestore = FirebaseFirestore.getInstance()

        val user = auth.currentUser
        if (user == null) {
            startActivity(Intent(this, AuthActivity::class.java))
            finish()
            return
        }

        binding.leaderboardRecyclerView.layoutManager = LinearLayoutManager(this)
        binding.leaderboardRecyclerView.adapter = LeaderboardAdapter()

        binding.scanButton.setOnClickListener {
            startActivity(Intent(this, ScannerActivity::class.java))
        }
    }

    override fun onStart() {
        super.onStart()
        auth.currentUser?.uid?.let { uid ->
            listenToUserPoints(uid)
            listenToLeaderboard()
        }
    }

    override fun onStop() {
        super.onStop()
        userListenerRegistration?.remove()
        leaderboardListenerRegistration?.remove()
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_home, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_logout -> {
                auth.signOut()
                startActivity(Intent(this, AuthActivity::class.java))
                finish()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun listenToUserPoints(uid: String) {
        val userRef = firestore.collection("users").document(uid)
        userListenerRegistration = userRef.addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener

            val newPoints = snapshot.getLong("points") ?: 0L
            binding.pointsTextView.text = newPoints.toString()

            lastPoints?.let { old ->
                if (newPoints > old) {
                    showPointsCelebration(newPoints - old)
                }
            }
            lastPoints = newPoints
        }
    }

    private fun listenToLeaderboard() {
        leaderboardListenerRegistration = firestore.collection("users")
            .orderBy("points", Query.Direction.DESCENDING)
            .limit(10)
            .addSnapshotListener { snapshot, e ->
                if (e != null || snapshot == null) return@addSnapshotListener

                val list = snapshot.documents.mapIndexed { index, doc ->
                    LeaderboardItem(
                        rank = index + 1,
                        name = doc.getString("name") ?: "Player ${index + 1}",
                        points = doc.getLong("points") ?: 0L
                    )
                }
                (binding.leaderboardRecyclerView.adapter as? LeaderboardAdapter)?.submitList(list)
            }
    }

    private fun showPointsCelebration(delta: Long) {
        Toast.makeText(this, "You earned +$delta points!", Toast.LENGTH_SHORT).show()
        val lottie: LottieAnimationView = binding.pointsLottie
        lottie.visibility = View.VISIBLE
        lottie.playAnimation()
        lottie.addAnimatorUpdateListener {
            if (!lottie.isAnimating) {
                lottie.visibility = View.GONE
            }
        }
    }
}

