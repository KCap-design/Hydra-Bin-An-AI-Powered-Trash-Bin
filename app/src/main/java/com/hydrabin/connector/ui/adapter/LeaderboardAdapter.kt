package com.hydrabin.connector.ui.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.hydrabin.connector.R
import com.hydrabin.connector.ui.model.LeaderboardItem

class LeaderboardAdapter :
    ListAdapter<LeaderboardItem, LeaderboardAdapter.ViewHolder>(DiffCallback()) {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val rankText: TextView = view.findViewById(R.id.rankText)
        val nameText: TextView = view.findViewById(R.id.nameText)
        val pointsText: TextView = view.findViewById(R.id.pointsText)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_leaderboard, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = getItem(position)
        holder.rankText.text = item.rank.toString()
        holder.nameText.text = item.name
        holder.pointsText.text = item.points.toString()
    }

    class DiffCallback : DiffUtil.ItemCallback<LeaderboardItem>() {
        override fun areItemsTheSame(oldItem: LeaderboardItem, newItem: LeaderboardItem): Boolean {
            return oldItem.rank == newItem.rank && oldItem.name == newItem.name
        }

        override fun areContentsTheSame(oldItem: LeaderboardItem, newItem: LeaderboardItem): Boolean {
            return oldItem == newItem
        }
    }
}

